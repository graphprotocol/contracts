import { SET_TARGET_ALLOCATION_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  createGovernanceTxBuilder,
  executeTxBatchDirect,
  saveGovernanceTxAndExit,
} from '@graphprotocol/deployment/lib/execute-governance.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { read } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import { encodeFunctionData } from 'viem'

/**
 * Configure PilotAllocation as IssuanceAllocator target
 *
 * Sets up PilotAllocation to receive tokens via allocator-minting from IssuanceAllocator.
 * Requires governor authority on IssuanceAllocator (via Controller).
 * If the provider has access to the governor key, executes directly.
 * Otherwise generates governance TX file.
 *
 * Idempotent: checks if already configured, skips if so.
 *
 * Usage:
 *   pnpm hardhat deploy --tags pilot-allocation-configure --network <network>
 */
const func: DeployScriptModule = async (env) => {
  const readFn = read(env)

  // Check if the provider can sign as the protocol governor
  const { governor, canSign } = await canSignAsGovernor(env)

  const [pilotAllocation, issuanceAllocator] = requireContracts(env, [
    Contracts.issuance.PilotAllocation,
    Contracts.issuance.IssuanceAllocator,
  ])

  env.showMessage(`\n========== Configure ${Contracts.issuance.PilotAllocation.name} ==========`)
  env.showMessage(`${Contracts.issuance.PilotAllocation.name}: ${pilotAllocation.address}`)
  env.showMessage(`${Contracts.issuance.IssuanceAllocator.name}: ${issuanceAllocator.address}`)

  // Check current allocation
  try {
    const allocation = (await readFn(issuanceAllocator, {
      functionName: 'getTargetAllocation',
      args: [pilotAllocation.address],
    })) as [bigint, bigint, bigint]

    if (allocation[1] > 0n || allocation[2] > 0n) {
      env.showMessage(`\n✓ ${Contracts.issuance.PilotAllocation.name} already configured as target`)
      env.showMessage(`  allocatorMintingRate: ${allocation[1]}`)
      env.showMessage(`  selfMintingRate: ${allocation[2]}`)
      return
    }
  } catch {
    // Not configured yet
  }

  // Get current issuance rate to determine allocation
  const issuancePerBlock = (await readFn(issuanceAllocator, { functionName: 'getIssuancePerBlock' })) as bigint
  if (issuancePerBlock === 0n) {
    env.showMessage(
      `\n⚠️  ${Contracts.issuance.IssuanceAllocator.name} rate is 0, cannot configure ${Contracts.issuance.PilotAllocation.name} allocation`,
    )
    env.showMessage(`   Configure ${Contracts.issuance.IssuanceAllocator.name} first with setIssuancePerBlock()`)
    return
  }

  // Configure PilotAllocation with allocator-minting (IA mints to it)
  // Default: small allocation for pilot testing
  const pilotRate = issuancePerBlock / 100n // 1% of total issuance

  env.showMessage(`\n🔨 Building configuration TX batch...`)
  env.showMessage(`  + setTargetAllocation(${pilotAllocation.address}, ${pilotRate}, 0)`)

  const builder = await createGovernanceTxBuilder(env, `configure-${Contracts.issuance.PilotAllocation.name}`)
  const data = encodeFunctionData({
    abi: SET_TARGET_ALLOCATION_ABI,
    functionName: 'setTargetAllocation',
    args: [pilotAllocation.address as `0x${string}`, pilotRate, 0n],
  })
  builder.addTx({ to: issuanceAllocator.address, value: '0', data })

  if (canSign) {
    env.showMessage('\n🔨 Executing configuration TX batch...\n')
    await executeTxBatchDirect(env, builder, governor)
    env.showMessage(
      `\n✅ ${Contracts.issuance.PilotAllocation.name} configured as ${Contracts.issuance.IssuanceAllocator.name} target`,
    )
  } else {
    saveGovernanceTxAndExit(env, builder, `${Contracts.issuance.PilotAllocation.name} configuration`)
  }
}

func.tags = Tags.pilotAllocationConfigure
func.dependencies = [
  actionTag(ComponentTags.PILOT_ALLOCATION, DeploymentActions.UPGRADE),
  actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.CONFIGURE),
]

export default func

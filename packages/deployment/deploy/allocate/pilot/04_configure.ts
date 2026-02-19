import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { execute, read } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Configure PilotAllocation as IssuanceAllocator target
 *
 * Sets up PilotAllocation to receive tokens via allocator-minting from IssuanceAllocator.
 * This requires IssuanceAllocator to be configured (deployer has GOVERNOR_ROLE or governance).
 *
 * Idempotent: checks if already configured, skips if so.
 *
 * Usage:
 *   pnpm hardhat deploy --tags pilot-allocation-configure --network <network>
 */
const func: DeployScriptModule = async (env) => {
  const readFn = read(env)
  const executeFn = execute(env)

  // Get protocol governor from Controller
  const governor = await getGovernor(env)

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

  env.showMessage(`\n🔨 Configuring ${Contracts.issuance.PilotAllocation.name}...`)
  env.showMessage(`  Setting allocatorMintingRate: ${pilotRate} (1% of ${issuancePerBlock})`)

  try {
    await executeFn(issuanceAllocator, {
      account: governor,
      functionName: 'setTargetAllocation',
      args: [pilotAllocation.address, pilotRate, 0n], // allocatorMintingRate, selfMintingRate (PA doesn't self-mint)
    })
    env.showMessage(
      `\n✅ ${Contracts.issuance.PilotAllocation.name} configured as ${Contracts.issuance.IssuanceAllocator.name} target`,
    )
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error)
    env.showMessage(`\n⚠️  Configuration failed: ${errorMessage.slice(0, 100)}...`)
    env.showMessage(`   This may require governance execution if deployer no longer has GOVERNOR_ROLE`)
  }
}

func.tags = Tags.pilotAllocationConfigure
func.dependencies = [
  actionTag(ComponentTags.PILOT_ALLOCATION, DeploymentActions.UPGRADE),
  actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.CONFIGURE),
]

export default func

import { REWARDS_MANAGER_DEPRECATED_ABI, SET_TARGET_ALLOCATION_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { requireRewardsManagerUpgraded } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { execute, graph, read, tx } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * Configure ${Contracts.issuance.IssuanceAllocator.name} initial state (deployer account)
 *
 * Configuration steps (IssuanceAllocator.md steps 2-3):
 * 2. Set issuance rate to match RewardsManager
 * 3. Configure RM as 100% self-minting target
 *
 * Requires deployer to have GOVERNOR_ROLE (granted during initialization in step 1).
 * PAUSE_ROLE will be granted in step 6 (transfer governance script).
 * Idempotent: checks on-chain state, skips if already configured.
 *
 * Usage:
 *   pnpm hardhat deploy --tags issuance-allocator-configure --network <network>
 */
const func: DeployScriptModule = async (env) => {
  const readFn = read(env)
  const executeFn = execute(env)

  const deployer = requireDeployer(env)

  const [issuanceAllocator, rewardsManager] = requireContracts(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
  ])

  // Create viem client for direct contract calls
  const client = graph.getPublicClient(env)

  // Check if RewardsManager supports IIssuanceTarget (has been upgraded)
  // Throws error if not upgraded
  await requireRewardsManagerUpgraded(client as PublicClient, rewardsManager.address, env)

  env.showMessage(`\n========== Configure ${Contracts.issuance.IssuanceAllocator.name} ==========`)
  env.showMessage(`${Contracts.issuance.IssuanceAllocator.name}: ${issuanceAllocator.address}`)
  env.showMessage(`${Contracts.horizon.RewardsManager.name}: ${rewardsManager.address}`)
  env.showMessage(`Deployer: ${deployer}\n`)

  // Get role constants
  const GOVERNOR_ROLE = (await readFn(issuanceAllocator, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`

  // Check current state
  env.showMessage('📋 Checking current configuration...\n')

  const checks = {
    issuanceRate: false,
    rmAllocation: false,
  }

  // Check issuance rate
  // Note: Use viem directly for RM because synced deployment has empty ABI
  const rmIssuanceRate = (await client.readContract({
    address: rewardsManager.address as `0x${string}`,
    abi: REWARDS_MANAGER_DEPRECATED_ABI,
    functionName: 'issuancePerBlock',
  })) as bigint
  const iaIssuanceRate = (await readFn(issuanceAllocator, { functionName: 'getIssuancePerBlock' })) as bigint
  checks.issuanceRate = iaIssuanceRate === rmIssuanceRate && iaIssuanceRate > 0n
  env.showMessage(`  Issuance rate: ${checks.issuanceRate ? '✓' : '✗'} (IA: ${iaIssuanceRate}, RM: ${rmIssuanceRate})`)

  // Check RM allocation (should be 100% self-minting)
  try {
    const rmAllocation = (await readFn(issuanceAllocator, {
      functionName: 'getTargetAllocation',
      args: [rewardsManager.address],
    })) as { totalAllocationRate: bigint; allocatorMintingRate: bigint; selfMintingRate: bigint }
    const expectedSelfMinting = iaIssuanceRate > 0n ? iaIssuanceRate : rmIssuanceRate
    checks.rmAllocation =
      rmAllocation.allocatorMintingRate === 0n && rmAllocation.selfMintingRate === expectedSelfMinting
    env.showMessage(
      `  RM allocation: ${checks.rmAllocation ? '✓' : '✗'} (allocator: ${rmAllocation.allocatorMintingRate}, self: ${rmAllocation.selfMintingRate})`,
    )
  } catch (error) {
    env.showMessage(`  RM allocation: ✗ (error reading: ${error})`)
  }

  // Check deployer role (informational - determines who can execute missing config)
  const deployerHasGovernorRole = (await readFn(issuanceAllocator, {
    functionName: 'hasRole',
    args: [GOVERNOR_ROLE, deployer],
  })) as boolean
  env.showMessage(`  Deployer GOVERNOR_ROLE: ${deployerHasGovernorRole ? '✓' : '✗'} (${deployer})`)

  // Note: PAUSE_ROLE will be granted in step 6 (transfer governance)

  // Configuration complete?
  const configurationComplete = Object.values(checks).every(Boolean)
  if (configurationComplete) {
    env.showMessage(`\n✅ ${Contracts.issuance.IssuanceAllocator.name} already configured\n`)
    return
  }

  // Check if deployer has permission to execute missing configuration
  // If governance has been transferred, configuration must be done via governance TX
  if (!deployerHasGovernorRole) {
    env.showMessage('\n❌ Configuration incomplete but deployer does not have GOVERNOR_ROLE')
    env.showMessage('   Governance has been transferred - this configuration must be done via governance TX')
    env.showMessage(`   Missing configuration:`)
    if (!checks.issuanceRate) {
      env.showMessage(`     - Issuance rate (currently: ${iaIssuanceRate})`)
    }
    if (!checks.rmAllocation) {
      env.showMessage(`     - RM allocation (not configured)`)
    }
    env.showMessage(`\n   This should not happen in normal deployment flow.`)
    env.showMessage(`   Configuration (step 5) should complete before governance transfer (step 6).\n`)
    process.exit(1)
  }

  // Execute configuration as deployer
  env.showMessage('\n🔨 Executing configuration...\n')

  // Step 2: Set issuance rate
  if (!checks.issuanceRate) {
    env.showMessage(`  Setting issuance rate to ${rmIssuanceRate}...`)
    await executeFn(issuanceAllocator, {
      account: deployer,
      functionName: 'setIssuancePerBlock',
      args: [rmIssuanceRate],
    })
    env.showMessage('  ✓ setIssuancePerBlock executed')
  }

  // Step 3: Configure RM allocation (3-arg version: target, allocatorMintingRate, selfMintingRate)
  // Note: Use tx() with encoded data to select the 3-arg overload (rocketh picks wrong one)
  if (!checks.rmAllocation) {
    const txFn = tx(env)
    const rate = iaIssuanceRate > 0n ? iaIssuanceRate : rmIssuanceRate
    env.showMessage(`  Setting RM allocation (0, ${rate})...`)
    const data = encodeFunctionData({
      abi: SET_TARGET_ALLOCATION_ABI,
      functionName: 'setTargetAllocation',
      args: [rewardsManager.address as `0x${string}`, 0n, rate],
    })
    await txFn({ account: deployer, to: issuanceAllocator.address, data })
    env.showMessage('  ✓ setTargetAllocation executed')
  }

  env.showMessage(`\n✅ ${Contracts.issuance.IssuanceAllocator.name} configuration complete!\n`)
}

func.tags = Tags.issuanceAllocatorConfigure
func.dependencies = [
  actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.DEPLOY),
  ComponentTags.REWARDS_MANAGER_UPGRADE,
]

export default func

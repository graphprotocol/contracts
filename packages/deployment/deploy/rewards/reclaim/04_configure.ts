import { REWARDS_MANAGER_ABI } from '@graphprotocol/deployment/lib/abis.js'
import {
  getReclaimAddress,
  RECLAIM_CONTRACT_NAMES,
  RECLAIM_REASONS,
  type ReclaimReasonKey,
} from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  createGovernanceTxBuilder,
  executeTxBatchDirect,
  saveGovernanceTxAndExit,
} from '@graphprotocol/deployment/lib/execute-governance.js'
import { requireContract } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import { encodeFunctionData } from 'viem'

/**
 * Configure RewardsManager with reclaim addresses
 *
 * Sets the reclaim addresses on RewardsManager for token recovery.
 * This requires RewardsManager to be upgraded (governance operation).
 *
 * Configured reasons:
 * - INDEXER_INELIGIBLE → ReclaimedRewardsForIndexerIneligible
 * - SUBGRAPH_DENIED → ReclaimedRewardsForSubgraphDenied
 * - STALE_POI → ReclaimedRewardsForStalePoi
 * - ZERO_POI → ReclaimedRewardsForZeroPoi
 * - CLOSE_ALLOCATION → ReclaimedRewardsForCloseAllocation
 *
 * Idempotent: checks if already configured, skips if so.
 * If the provider has access to the governor key, executes directly.
 * Otherwise generates governance TX file.
 *
 * Usage:
 *   pnpm hardhat deploy --tags rewards-reclaim-configure --network <network>
 */
const func: DeployScriptModule = async (env) => {
  const client = graph.getPublicClient(env)

  // Check if the provider can sign as the protocol governor
  const { governor, canSign } = await canSignAsGovernor(env)

  const rewardsManager = requireContract(env, Contracts.horizon.RewardsManager)

  env.showMessage(`\n========== Configure ${Contracts.horizon.RewardsManager.name} Reclaim ==========`)
  env.showMessage(`${Contracts.horizon.RewardsManager.name}: ${rewardsManager.address}`)

  // Find deployed reclaim addresses
  const reclaimAddresses: { name: string; address: string; reasonKey: ReclaimReasonKey }[] = []

  for (const [reasonKey, contractName] of Object.entries(RECLAIM_CONTRACT_NAMES)) {
    const deployment = env.getOrNull(contractName)
    if (deployment) {
      reclaimAddresses.push({
        name: contractName,
        address: deployment.address,
        reasonKey: reasonKey as ReclaimReasonKey,
      })
    }
  }

  if (reclaimAddresses.length === 0) {
    env.showMessage(`\n⚠️  No reclaim addresses deployed, skipping configuration`)
    return
  }

  env.showMessage(`\nFound ${reclaimAddresses.length} reclaim address(es):`)
  for (const { name, address } of reclaimAddresses) {
    env.showMessage(`  ${name}: ${address}`)
  }

  // Check current configuration
  const needsConfiguration: typeof reclaimAddresses = []

  for (const reclaim of reclaimAddresses) {
    const reason = RECLAIM_REASONS[reclaim.reasonKey]

    // Check if RM has this reclaim address configured for this reason
    const currentReclaim = await getReclaimAddress(client, rewardsManager.address, reason)
    if (currentReclaim && currentReclaim.toLowerCase() === reclaim.address.toLowerCase()) {
      env.showMessage(`\n✓ ${reclaim.name} already configured on RewardsManager`)
      continue
    }
    needsConfiguration.push(reclaim)
  }

  if (needsConfiguration.length === 0) {
    env.showMessage(`\n✓ All reclaim addresses already configured`)
    return
  }

  // Build TX batch
  env.showMessage(`\n🔨 Building configuration TX batch...`)

  const builder = await createGovernanceTxBuilder(env, `configure-${Contracts.horizon.RewardsManager.name}-Reclaim`)

  for (const reclaim of needsConfiguration) {
    const reason = RECLAIM_REASONS[reclaim.reasonKey]

    const data = encodeFunctionData({
      abi: REWARDS_MANAGER_ABI,
      functionName: 'setReclaimAddress',
      args: [reason as `0x${string}`, reclaim.address as `0x${string}`],
    })
    builder.addTx({ to: rewardsManager.address, value: '0', data })
    env.showMessage(`  + setReclaimAddress(${reclaim.reasonKey}, ${reclaim.address})`)
  }

  if (canSign) {
    env.showMessage('\n🔨 Executing configuration TX batch...\n')
    await executeTxBatchDirect(env, builder, governor)
    env.showMessage(`\n✅ ${Contracts.horizon.RewardsManager.name} reclaim configuration complete!`)
  } else {
    saveGovernanceTxAndExit(env, builder, `${Contracts.horizon.RewardsManager.name} reclaim configuration`)
  }
}

func.tags = Tags.rewardsReclaimConfigure
func.dependencies = [actionTag(ComponentTags.REWARDS_RECLAIM, DeploymentActions.UPGRADE), ComponentTags.REWARDS_MANAGER]

export default func

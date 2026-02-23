import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, SpecialTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { deployProxyContract } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy DirectAllocation proxies as reclaim addresses
 *
 * This script deploys DirectAllocation proxy instances for each reclaim reason.
 * All proxies share the DirectAllocation_Implementation deployed by direct-allocation-impl.
 *
 * Deployed contracts:
 * - ReclaimedRewardsForIndexerIneligible
 * - ReclaimedRewardsForSubgraphDenied
 * - ReclaimedRewardsForStalePoi
 * - ReclaimedRewardsForZeroPoi
 * - ReclaimedRewardsForCloseAllocation
 *
 * Usage:
 *   pnpm hardhat deploy --tags rewards-reclaim-deploy --network <network>
 */

// Reclaim contracts that share DirectAllocation implementation
const RECLAIM_CONTRACTS = [
  Contracts.issuance.ReclaimedRewardsForIndexerIneligible,
  Contracts.issuance.ReclaimedRewardsForSubgraphDenied,
  Contracts.issuance.ReclaimedRewardsForStalePoi,
  Contracts.issuance.ReclaimedRewardsForZeroPoi,
  Contracts.issuance.ReclaimedRewardsForCloseAllocation,
] as const

const func: DeployScriptModule = async (env) => {
  env.showMessage(`\n📦 Deploying DirectAllocation reclaim address proxies...`)
  env.showMessage(`   Shared implementation: ${Contracts.issuance.DirectAllocation_Implementation.name}`)

  for (const contract of RECLAIM_CONTRACTS) {
    await deployProxyContract(env, {
      contract,
      sharedImplementation: Contracts.issuance.DirectAllocation_Implementation,
      // initializeArgs defaults to [governor]
    })
  }

  env.showMessage('\n✓ Reclaim addresses deployment complete')
}

func.tags = Tags.rewardsReclaimDeploy
func.dependencies = [SpecialTags.SYNC, ComponentTags.DIRECT_ALLOCATION_IMPL, ComponentTags.REWARDS_MANAGER]

export default func

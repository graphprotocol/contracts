import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { upgradeImplementation } from '@graphprotocol/deployment/lib/upgrade-implementation.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// ReclaimedRewards Upgrade
//
// Upgrades ReclaimedRewardsFor* proxies to DirectAllocation implementation via per-proxy ProxyAdmin.
// The implementation is shared across multiple allocation proxies.
//
// Workflow:
// 1. Check for pending implementation in address book (set by direct-allocation-impl)
// 2. Generate governance TX (upgradeAndCall to per-proxy ProxyAdmin) for each proxy
// 3. Fork mode: execute via governor impersonation
// 4. Production: output TX file for Safe execution
//
// Usage:
//   FORK_NETWORK=arbitrumSepolia npx hardhat deploy --tags rewards-reclaim-upgrade --network localhost

// Reclaim contracts that share DirectAllocation implementation
const RECLAIM_CONTRACTS = [
  Contracts.issuance.ReclaimedRewardsForIndexerIneligible,
  Contracts.issuance.ReclaimedRewardsForSubgraphDenied,
  Contracts.issuance.ReclaimedRewardsForStalePoi,
  Contracts.issuance.ReclaimedRewardsForZeroPoi,
  Contracts.issuance.ReclaimedRewardsForCloseAllocation,
] as const

const func: DeployScriptModule = async (env) => {
  for (const contract of RECLAIM_CONTRACTS) {
    await upgradeImplementation(env, contract, {
      implementationName: 'DirectAllocation',
    })
  }
}

func.tags = Tags.rewardsReclaimUpgrade
func.dependencies = [
  actionTag(ComponentTags.REWARDS_RECLAIM, DeploymentActions.DEPLOY),
  ComponentTags.DIRECT_ALLOCATION_IMPL,
]

export default func

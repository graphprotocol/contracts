import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { upgradeImplementation } from '@graphprotocol/deployment/lib/upgrade-implementation.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// ReclaimedRewards Upgrade
//
// Upgrades ReclaimedRewards proxy to DirectAllocation implementation via per-proxy ProxyAdmin.
//
// Workflow:
// 1. Check for pending implementation in address book (set by direct-allocation-impl)
// 2. Generate governance TX (upgradeAndCall to per-proxy ProxyAdmin)
// 3. Fork mode: execute via governor impersonation
// 4. Production: output TX file for Safe execution
//
// Usage:
//   FORK_NETWORK=arbitrumSepolia npx hardhat deploy --tags RewardsReclaim:upgrade --network localhost

const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.UPGRADE)) return
  await syncComponentsFromRegistry(env, [
    Contracts.issuance.DirectAllocation_Implementation,
    Contracts.issuance.ReclaimedRewards,
  ])
  await upgradeImplementation(env, Contracts.issuance.ReclaimedRewards, {
    implementationName: 'DirectAllocation',
  })
  await syncComponentsFromRegistry(env, [Contracts.issuance.ReclaimedRewards])
}

func.tags = [ComponentTags.REWARDS_RECLAIM]
func.dependencies = [ComponentTags.DIRECT_ALLOCATION_IMPL]
func.skip = async () => shouldSkipAction(DeploymentActions.UPGRADE)

export default func

import { RECLAIM_CONTRACT_NAMES } from '@graphprotocol/deployment/lib/contract-checks.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireUpgradeExecuted } from '@graphprotocol/deployment/lib/execute-governance.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * RewardsReclaim end state - deployed, upgraded, and configured
 *
 * Aggregate tag that ensures ReclaimedRewardsFor* contracts are fully ready:
 * - Proxies and shared implementation deployed
 * - Proxies upgraded to latest implementation
 * - Configured on RewardsManager
 *
 * Usage:
 *   pnpm hardhat deploy --tags rewards-reclaim --network <network>
 */
const func: DeployScriptModule = async (env) => {
  // Check all reclaim address proxies for pending upgrades
  for (const contractName of Object.values(RECLAIM_CONTRACT_NAMES)) {
    requireUpgradeExecuted(env, contractName)
  }
  env.showMessage(`\n✓ RewardsReclaim ready`)
}

func.tags = Tags.rewardsReclaim
func.dependencies = [
  actionTag(ComponentTags.REWARDS_RECLAIM, DeploymentActions.DEPLOY),
  actionTag(ComponentTags.REWARDS_RECLAIM, DeploymentActions.UPGRADE),
  actionTag(ComponentTags.REWARDS_RECLAIM, DeploymentActions.CONFIGURE),
]

export default func

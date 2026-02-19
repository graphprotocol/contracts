import { ComponentTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireUpgradeExecuted } from '@graphprotocol/deployment/lib/execute-governance.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * RewardsManager end state - deployed and upgraded
 *
 * Usage:
 *   pnpm hardhat deploy --tags rewards-manager --network <network>
 */
const func: DeployScriptModule = async (env) => {
  requireUpgradeExecuted(env, 'RewardsManager')
  env.showMessage(`\n✓ RewardsManager ready`)
}

func.tags = Tags.rewardsManager
func.dependencies = [ComponentTags.REWARDS_MANAGER_DEPLOY, ComponentTags.REWARDS_MANAGER_UPGRADE]

export default func

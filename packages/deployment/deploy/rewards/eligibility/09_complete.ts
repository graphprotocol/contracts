import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireUpgradeExecuted } from '@graphprotocol/deployment/lib/execute-governance.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * RewardsEligibilityOracle complete - verifies full deployment
 *
 * Aggregate tag: runs deploy, upgrade, configure steps.
 * Transfer-governance is separate (explicit action to relinquish control).
 *
 * See: docs/deploy/RewardsEligibilityOracleDeployment.md
 *
 * Usage:
 *   pnpm hardhat deploy --tags rewards-eligibility --network <network>
 */
const func: DeployScriptModule = async (env) => {
  requireUpgradeExecuted(env, Contracts.issuance.RewardsEligibilityOracle.name)
  env.showMessage(`\n✓ ${Contracts.issuance.RewardsEligibilityOracle.name} ready`)
}

func.tags = Tags.rewardsEligibility
func.dependencies = [
  actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.DEPLOY),
  actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.UPGRADE),
  actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.CONFIGURE),
  actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.TRANSFER),
  actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.INTEGRATE),
  actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.VERIFY),
]

export default func

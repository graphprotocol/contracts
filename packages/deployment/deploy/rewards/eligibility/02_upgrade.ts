import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { upgradeImplementation } from '@graphprotocol/deployment/lib/upgrade-implementation.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Upgrade RewardsEligibilityOracle to pending implementation
 *
 * Generates governance TX batch for proxy upgrade, then exits.
 * Execute separately via: pnpm hardhat deploy:execute-governance
 *
 * See: docs/deploy/RewardsEligibilityOracleDeployment.md
 *
 * Usage:
 *   pnpm hardhat deploy --tags rewards-eligibility-upgrade --network <network>
 */

const func: DeployScriptModule = async (env) => {
  await upgradeImplementation(env, Contracts.issuance.RewardsEligibilityOracle)
}

func.tags = Tags.rewardsEligibilityUpgrade
func.dependencies = [actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.DEPLOY)]

export default func

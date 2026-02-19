import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { SpecialTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { deployProxyContract, requireGraphToken } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy RewardsEligibilityOracle proxy and implementation
 *
 * Deploys OZ v5 TransparentUpgradeableProxy with atomic initialization.
 * Deployer receives GOVERNOR_ROLE (temporary, for configuration).
 *
 * See: docs/deploy/RewardsEligibilityOracleDeployment.md
 *
 * Usage:
 *   pnpm hardhat deploy --tags rewards-eligibility-deploy --network <network>
 */

const func: DeployScriptModule = async (env) => {
  const graphToken = requireGraphToken(env).address

  env.showMessage(`\n📦 Deploying ${Contracts.issuance.RewardsEligibilityOracle.name} with GraphToken: ${graphToken}`)

  await deployProxyContract(env, {
    contract: Contracts.issuance.RewardsEligibilityOracle,
    constructorArgs: [graphToken],
  })
}

func.tags = Tags.rewardsEligibilityDeploy
func.dependencies = [SpecialTags.SYNC]

export default func

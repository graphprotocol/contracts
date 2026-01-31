import { applyConfiguration } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { checkREORole, getREOConditions } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

/**
 * Configure RewardsEligibilityOracle (params + roles)
 *
 * See: docs/deploy/RewardsEligibilityOracleDeployment.md
 */
const func: DeployScriptModule = async (env) => {
  const deployer = requireDeployer(env)
  const [reo] = requireContracts(env, [Contracts.issuance.RewardsEligibilityOracle])
  const client = graph.getPublicClient(env) as PublicClient

  const canExecuteDirectly = (await checkREORole(client, reo.address, 'GOVERNOR_ROLE', deployer)).hasRole

  await applyConfiguration(env, client, await getREOConditions(env), {
    contractName: Contracts.issuance.RewardsEligibilityOracle.name,
    contractAddress: reo.address,
    canExecuteDirectly,
    executor: deployer,
  })
}

func.tags = Tags.rewardsEligibilityConfigure
func.dependencies = [actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.DEPLOY)]

export default func

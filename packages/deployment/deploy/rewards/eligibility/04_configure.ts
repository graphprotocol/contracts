import { applyConfiguration } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { getREOConditions } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

/**
 * Configure RewardsEligibilityOracle (params + roles)
 *
 * Uses canSignAsGovernor() to check if the provider has access to the governor
 * account (e.g., via mnemonic on localNetwork). If so, executes governance TXs
 * directly. Otherwise, saves TX batch for separate governance execution.
 *
 * See: docs/deploy/RewardsEligibilityOracleDeployment.md
 */
const func: DeployScriptModule = async (env) => {
  const [reo] = requireContracts(env, [Contracts.issuance.RewardsEligibilityOracle])
  const client = graph.getPublicClient(env) as PublicClient

  const { governor, canSign } = await canSignAsGovernor(env)

  await applyConfiguration(env, client, await getREOConditions(env), {
    contractName: Contracts.issuance.RewardsEligibilityOracle.name,
    contractAddress: reo.address,
    canExecuteDirectly: canSign,
    executor: governor,
  })
}

func.tags = Tags.rewardsEligibilityConfigure
func.dependencies = [actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.DEPLOY)]

export default func

import { applyConfiguration } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { createRMIntegrationCondition } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

/**
 * Integrate RewardsEligibilityOracle with RewardsManager
 *
 * See: docs/deploy/RewardsEligibilityOracleDeployment.md
 */
const func: DeployScriptModule = async (env) => {
  const [reo, rm] = requireContracts(env, [
    Contracts.issuance.RewardsEligibilityOracle,
    Contracts.horizon.RewardsManager,
  ])
  const client = graph.getPublicClient(env) as PublicClient

  // Apply: RM.rewardsEligibilityOracle = REO (always governance TX)
  await applyConfiguration(env, client, [createRMIntegrationCondition(reo.address)], {
    contractName: `${Contracts.horizon.RewardsManager.name}-REO`,
    contractAddress: rm.address,
    canExecuteDirectly: false,
  })
}

func.tags = Tags.rewardsEligibilityIntegrate
func.dependencies = [Tags.rewardsEligibilityTransfer[0], ComponentTags.REWARDS_MANAGER]

export default func

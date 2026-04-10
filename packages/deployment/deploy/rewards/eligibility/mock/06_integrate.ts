import { applyConfiguration } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { createRMIntegrationCondition } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { ComponentTags, DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'

/**
 * Integrate MockRewardsEligibilityOracle with RewardsManager (testnet only)
 *
 * Points RewardsManager at the mock so indexers can control their own eligibility.
 */
export default createActionModule(
  Contracts.issuance.RewardsEligibilityOracleMock,
  DeploymentActions.INTEGRATE,
  async (env) => {
    const [reo, rm] = requireContracts(env, [
      Contracts.issuance.RewardsEligibilityOracleMock,
      Contracts.horizon.RewardsManager,
    ])
    const client = graph.getPublicClient(env) as PublicClient

    const { governor, canSign } = await canSignAsGovernor(env)

    await applyConfiguration(env, client, [createRMIntegrationCondition(reo.address)], {
      contractName: `${Contracts.horizon.RewardsManager.name}-REO`,
      contractAddress: rm.address,
      canExecuteDirectly: canSign,
      executor: governor,
    })
  },
  { extraDependencies: [ComponentTags.REWARDS_MANAGER] },
)

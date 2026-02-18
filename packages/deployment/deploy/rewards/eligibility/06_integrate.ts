import { applyConfiguration } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { createRMIntegrationCondition } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { ComponentTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

/**
 * Integrate RewardsEligibilityOracle with RewardsManager
 *
 * Requires governor authority on the RewardsManager (via Controller).
 * If the provider has access to the governor key (e.g., mnemonic-derived accounts
 * in local network), executes directly. Otherwise generates governance TX file.
 *
 * See: docs/deploy/RewardsEligibilityOracleDeployment.md
 */
const func: DeployScriptModule = async (env) => {
  const [reo, rm] = requireContracts(env, [
    Contracts.issuance.RewardsEligibilityOracle,
    Contracts.horizon.RewardsManager,
  ])
  const client = graph.getPublicClient(env) as PublicClient

  // Check if the provider can sign as the protocol governor.
  // With a mnemonic (local network), all derived accounts are available.
  // With explicit keys (production), only configured accounts are available.
  const governor = await getGovernor(env)
  const accounts = (await env.network.provider.request({ method: 'eth_accounts' })) as string[]
  const canExecuteDirectly = accounts.some((a) => a.toLowerCase() === governor.toLowerCase())

  await applyConfiguration(env, client, [createRMIntegrationCondition(reo.address)], {
    contractName: `${Contracts.horizon.RewardsManager.name}-REO`,
    contractAddress: rm.address,
    canExecuteDirectly,
    executor: governor,
  })
}

func.tags = Tags.rewardsEligibilityIntegrate
func.dependencies = [Tags.rewardsEligibilityTransfer[0], ComponentTags.REWARDS_MANAGER]

export default func

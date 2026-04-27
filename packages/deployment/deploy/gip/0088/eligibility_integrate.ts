import { PROVIDER_ELIGIBILITY_MANAGEMENT_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { applyConfiguration } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { createRMIntegrationCondition } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { ComponentTags, GoalTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

/**
 * GIP-0088:eligibility-integrate — Set RewardsEligibilityOracle on RewardsManager
 *
 * Governance TX: RM.setProviderEligibilityOracle(REO_A)
 *
 * Skips if oracle already set (any value, not just REO_A) to avoid
 * accidentally overriding a live oracle configuration.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:eligibility-integrate --network <network>
 */
export default createActionModule(
  GoalTags.GIP_0088_ELIGIBILITY_INTEGRATE,
  async (env) => {
    await syncComponentsFromRegistry(env, [
      Contracts.issuance.RewardsEligibilityOracleA,
      Contracts.horizon.RewardsManager,
    ])
    const [reo, rm] = requireContracts(env, [
      Contracts.issuance.RewardsEligibilityOracleA,
      Contracts.horizon.RewardsManager,
    ])
    const client = graph.getPublicClient(env) as PublicClient

    // Check if oracle already set — skip if any oracle configured (don't override)
    try {
      const currentOracle = (await client.readContract({
        address: rm.address as `0x${string}`,
        abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
        functionName: 'getProviderEligibilityOracle',
      })) as string

      if (currentOracle !== ZERO_ADDRESS) {
        const isTarget = currentOracle.toLowerCase() === reo.address.toLowerCase()
        env.showMessage(`\n  ${isTarget ? '✓' : '○'} RM.providerEligibilityOracle already set: ${currentOracle}`)
        if (!isTarget) {
          env.showMessage(`    (not REO_A — skipping to avoid override)`)
        }
        env.showMessage('')
        return
      }
    } catch {
      // Function not available — RM not upgraded, skip
      env.showMessage(`\n  ○ RM does not support getProviderEligibilityOracle — skipping\n`)
      return
    }

    const { governor, canSign } = await canSignAsGovernor(env)

    await applyConfiguration(env, client, [createRMIntegrationCondition(reo.address)], {
      contractName: `${Contracts.horizon.RewardsManager.name}-REO`,
      contractAddress: rm.address,
      canExecuteDirectly: canSign,
      executor: governor,
    })
  },
  {
    dependencies: [ComponentTags.REWARDS_MANAGER, ComponentTags.REWARDS_ELIGIBILITY_A],
  },
)

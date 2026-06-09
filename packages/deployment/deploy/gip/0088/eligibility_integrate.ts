import { PROVIDER_ELIGIBILITY_MANAGEMENT_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { applyConfiguration } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { createRMIntegrationCondition } from '@graphprotocol/deployment/lib/contract-checks.js'
import {
  Contracts,
  eligibilityOracleContract,
  type EligibilityOracleContractName,
  type RegistryEntry,
} from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { getResolvedSettingsForEnv } from '@graphprotocol/deployment/lib/deployment-config.js'
import { ComponentTags, GoalTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { Environment } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

/**
 * Wire one eligibility-oracle target (RM or RAM) to its configured REO.
 *
 * `oracleName` is the configured REO contract name, or `undefined` when config
 * omits it — in which case this target gets no oracle and we no-op. Skips
 * (without overriding) if a different oracle is already live; that mismatch is
 * surfaced and fails the G12 gate (09_end), forcing a deliberate decision.
 */
async function integrateOracle(
  env: Environment,
  client: PublicClient,
  targetLabel: string,
  targetEntry: RegistryEntry,
  oracleName: EligibilityOracleContractName | undefined,
): Promise<void> {
  if (!oracleName) {
    env.showMessage(`\n  ○ ${targetLabel}: no eligibility oracle configured — skipping\n`)
    return
  }

  const reoEntry = eligibilityOracleContract(oracleName)
  await syncComponentsFromRegistry(env, [reoEntry, targetEntry])
  const [reo, target] = requireContracts(env, [reoEntry, targetEntry])

  // Check if oracle already set — skip if any oracle configured (don't override).
  try {
    const currentOracle = (await client.readContract({
      address: target.address as `0x${string}`,
      abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
      functionName: 'getProviderEligibilityOracle',
    })) as string

    if (currentOracle !== ZERO_ADDRESS) {
      const isTarget = currentOracle.toLowerCase() === reo.address.toLowerCase()
      env.showMessage(
        `\n  ${isTarget ? '✓' : '○'} ${targetLabel}.providerEligibilityOracle already set: ${currentOracle}`,
      )
      if (!isTarget) {
        env.showMessage(`    (not the configured ${oracleName} — skipping to avoid override)`)
      }
      env.showMessage('')
      return
    }
  } catch {
    // Function not available — target not upgraded, skip
    env.showMessage(`\n  ○ ${targetLabel} does not support getProviderEligibilityOracle — skipping\n`)
    return
  }

  const { governor, canSign } = await canSignAsGovernor(env)

  await applyConfiguration(env, client, [createRMIntegrationCondition(reo.address)], {
    contractName: `${target.name}-REO`,
    contractAddress: target.address,
    canExecuteDirectly: canSign,
    executor: governor,
  })
}

/**
 * GIP-0088:eligibility-integrate — Set the eligibility oracle on RM and RAM
 *
 * Governance TX: <target>.setProviderEligibilityOracle(<configured REO>) for
 * each of RewardsManager and RecurringAgreementManager that names an oracle in
 * config (`RewardsManager.eligibilityOracle` /
 * `RecurringAgreementManager.eligibilityOracle` in config/<network>.json5).
 *
 * RM and RAM are handled independently and on the same basis: a target whose
 * config omits the oracle field is skipped (no oracle wired).
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:eligibility-integrate --network <network>
 */
export default createActionModule(
  GoalTags.GIP_0088_ELIGIBILITY_INTEGRATE,
  async (env) => {
    const settings = await getResolvedSettingsForEnv(env)
    const client = graph.getPublicClient(env) as PublicClient

    await integrateOracle(
      env,
      client,
      'RM',
      Contracts.horizon.RewardsManager,
      settings.rewardsManager.eligibilityOracle,
    )
    await integrateOracle(
      env,
      client,
      'RAM',
      Contracts.issuance.RecurringAgreementManager,
      settings.recurringAgreementManager.eligibilityOracle,
    )
  },
  {
    // Ordering anchor for a combined `--tags GIP-0088` run: REO-A always deploys
    // in the upgrade phase, so this guarantees the eligibility components exist
    // before activation. The actual target REOs are resolved from config at
    // runtime (and skipped gracefully via requireContracts if not deployed).
    dependencies: [ComponentTags.REWARDS_MANAGER, ComponentTags.REWARDS_ELIGIBILITY_A],
  },
)

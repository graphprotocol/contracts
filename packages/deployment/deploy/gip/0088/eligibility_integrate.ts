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

/**
 * Wire one eligibility-oracle target (RM or RAM) to its configured REO.
 *
 * `oracleName` is the configured REO contract name, or `undefined` when config
 * omits it — in which case this target gets no oracle and we no-op. Config is
 * the source of truth: when the target's current oracle differs from the
 * configured REO it is re-pointed (overriding the prior value); when it already
 * matches it is a no-op. Skips only when the target isn't upgraded yet (it has
 * no oracle getter to read or setter to call).
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

  // Skip only if the target isn't upgraded yet (no oracle getter). Once it
  // supports the getter, config is the source of truth: applyConfiguration is
  // idempotent — it re-points the oracle to the configured REO when the current
  // value differs (overriding any prior oracle) and no-ops when it matches.
  try {
    await client.readContract({
      address: target.address as `0x${string}`,
      abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
      functionName: 'getProviderEligibilityOracle',
    })
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

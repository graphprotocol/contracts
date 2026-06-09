import {
  IISSUANCE_TARGET_INTERFACE_ID,
  PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
  SUBGRAPH_SERVICE_CLOSE_GUARD_ABI,
} from '@graphprotocol/deployment/lib/abis.js'
import { getAddressBookForType, getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import {
  addressEquals,
  checkIssuanceConnectComplete,
  isRewardsManagerUpgraded,
} from '@graphprotocol/deployment/lib/contract-checks.js'
import {
  Contracts,
  eligibilityOracleContract,
  type EligibilityOracleContractName,
  type RegistryEntry,
} from '@graphprotocol/deployment/lib/contract-registry.js'
import { getResolvedSettings } from '@graphprotocol/deployment/lib/deployment-config.js'
import { GoalTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { createStatusModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { showDetailedComponentStatus, showPendingGovernanceTxs } from '@graphprotocol/deployment/lib/status-detail.js'
import { getContractStatusLine, syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'

/**
 * GIP-0088 Status — Phase-structured deployment state display
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088 --network <network>
 */
export default createStatusModule(GoalTags.GIP_0088, async (env) => {
  const targetChainId = await getTargetChainIdFromEnv(env)
  const settings = getResolvedSettings(targetChainId)
  const rmOracleName = settings.rewardsManager.eligibilityOracle
  const ramOracleName = settings.recurringAgreementManager.eligibilityOracle
  // Distinct REO entries named by config (RM and/or RAM), for sync + display.
  const configuredReoEntries = [
    ...new Set([rmOracleName, ramOracleName].filter(Boolean) as EligibilityOracleContractName[]),
  ].map((n) => eligibilityOracleContract(n))

  // Sync the contracts this status touches via env.getOrNull so the read paths
  // work without depending on a separate global sync run.
  await syncComponentsFromRegistry(env, [
    Contracts.horizon.RewardsManager,
    Contracts.horizon.L2GraphToken,
    Contracts['subgraph-service'].SubgraphService,
    Contracts.issuance.IssuanceAllocator,
    Contracts.issuance.RecurringAgreementManager,
    ...configuredReoEntries,
  ])

  const client = graph.getPublicClient(env) as PublicClient
  const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

  // Print one target's eligibility-integrate status: on-chain oracle vs config.
  const oracleStatusLine = async (
    label: string,
    targetAddress: string,
    oracleName: EligibilityOracleContractName | undefined,
  ): Promise<void> => {
    let current: string
    try {
      current = (await client.readContract({
        address: targetAddress as `0x${string}`,
        abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
        functionName: 'getProviderEligibilityOracle',
      })) as string
    } catch {
      env.showMessage(`  ○ eligibility-integrate (${label}): not upgraded`)
      return
    }
    if (oracleName) {
      const reo = env.getOrNull(oracleName)
      if (!reo) {
        env.showMessage(`  ○ eligibility-integrate (${label}): configured ${oracleName} not deployed`)
      } else {
        const ok = addressEquals(current, reo.address)
        env.showMessage(
          `  ${ok ? '✓' : '✗'} eligibility-integrate (${label}): ${label}.providerEligibilityOracle == ${oracleName}`,
        )
      }
    } else {
      const unset = current === ZERO_ADDRESS
      env.showMessage(
        `  ${unset ? '✓' : '✗'} eligibility-integrate (${label}): no oracle configured${unset ? ' (unset)' : ` — but set to ${current}`}`,
      )
    }
  }

  env.showMessage('\n========== GIP-0088: Full Deployment Status ==========')

  // --- Upgrade phase ---
  env.showMessage('\nUpgrade:')

  const upgradeContracts: RegistryEntry[] = [
    Contracts.horizon.RewardsManager,
    Contracts.horizon.HorizonStaking,
    Contracts['subgraph-service'].SubgraphService,
    Contracts['subgraph-service'].DisputeManager,
    Contracts.horizon.PaymentsEscrow,
    Contracts.horizon.L2Curation,
    Contracts.horizon.RecurringCollector,
  ]

  const rm = env.getOrNull('RewardsManager')

  for (const contract of upgradeContracts) {
    const ab = getAddressBookForType(contract.addressBook, targetChainId)

    const result = await getContractStatusLine(client, contract.addressBook, ab, contract.name)
    env.showMessage(`  ${result.line}`)

    // RM: semantic check — does the on-chain code support IIssuanceTarget?
    if (contract === Contracts.horizon.RewardsManager && result.exists && rm) {
      const upgraded = await isRewardsManagerUpgraded(client, rm.address)
      env.showMessage(`        ${upgraded ? '✓' : '✗'} implements IIssuanceTarget (${IISSUANCE_TARGET_INTERFACE_ID})`)
    }
  }

  // --- Eligibility phase ---
  env.showMessage('\nEligibility:')
  if (configuredReoEntries.length === 0) {
    env.showMessage('  ○ no eligibility oracle configured for RM or RAM')
  } else {
    for (const entry of configuredReoEntries) {
      await showDetailedComponentStatus(env, entry, { showHints: false })
    }
  }

  // --- Issuance phase ---
  env.showMessage('\nIssuance:')
  await showDetailedComponentStatus(env, Contracts.issuance.IssuanceAllocator, { showHints: false })

  const ram = env.getOrNull('RecurringAgreementManager')
  if (ram) {
    await showDetailedComponentStatus(env, Contracts.issuance.RecurringAgreementManager, { showHints: false })
  } else {
    env.showMessage(`  ○ RecurringAgreementManager not deployed`)
  }

  // --- Activation status ---
  env.showMessage('\n--- Activation ---')

  // eligibility-integrate: each target's providerEligibilityOracle == config
  if (rm) {
    const upgraded = await isRewardsManagerUpgraded(client, rm.address)
    if (upgraded) {
      await oracleStatusLine('RM', rm.address, rmOracleName)
      if (ram) await oracleStatusLine('RAM', ram.address, ramOracleName)

      // issuance-connect: strict end-state — shared helper matches issuance_connect.ts's
      // idempotency gate so status / 09_end / build-batch all agree on "done".
      const ia = env.getOrNull('IssuanceAllocator')
      const gt = env.getOrNull('L2GraphToken')
      if (ia && gt) {
        const connect = await checkIssuanceConnectComplete(client, ia.address, rm.address, gt.address)
        const reasons: string[] = []
        if (!connect.iaIntegrated) reasons.push('not connected')
        if (!connect.iaMinter) reasons.push('no minter role')
        if (!connect.ratesAligned) reasons.push('IA/RM rate mismatch')
        if (!connect.rmAllocationShape) reasons.push('RM allocation shape wrong')
        if (!connect.fullyAllocated) reasons.push('IA not 100% allocated')
        env.showMessage(
          `  ${connect.complete ? '✓' : '✗'} issuance-connect: RM ↔ IA${reasons.length ? ` (${reasons.join(', ')})` : ''}`,
        )
      } else {
        env.showMessage(`  ○ issuance-connect: IA not deployed`)
      }

      // issuance-allocate: IA.getTargetAllocation(RAM) configured
      if (ram) {
        env.showMessage(`  ○ issuance-allocate: check via --tags ${GoalTags.GIP_0088_ISSUANCE_ALLOCATE}`)
      } else {
        env.showMessage(`  ○ issuance-allocate: RAM not deployed`)
      }
    } else {
      env.showMessage('  ○ RM not upgraded (activation blocked)')
    }
  } else {
    env.showMessage('  ○ RM not in address book')
  }

  // --- Optional status ---
  env.showMessage('\n--- Optional (not planned) ---')

  // issuance-close-guard
  const ss = env.getOrNull('SubgraphService')
  if (ss) {
    try {
      const closeGuard = (await client.readContract({
        address: ss.address as `0x${string}`,
        abi: SUBGRAPH_SERVICE_CLOSE_GUARD_ABI,
        functionName: 'getBlockClosingAllocationWithActiveAgreement',
      })) as boolean
      env.showMessage(`  ${closeGuard ? '✓' : '○'} issuance-close-guard: blockClosingAllocation = ${closeGuard}`)
    } catch {
      env.showMessage(`  ○ issuance-close-guard: SS not upgraded`)
    }
  } else {
    env.showMessage(`  ○ issuance-close-guard: SS not deployed`)
  }

  // --- Actions ---
  env.showMessage('\n--- Actions ---')
  env.showMessage('  Deploy & upgrade:')
  env.showMessage('    --tags GIP-0088:upgrade,<deploy|configure|transfer|upgrade>')
  env.showMessage('  Activation (after upgrades executed):')
  env.showMessage('    --tags GIP-0088:eligibility-integrate')
  env.showMessage('    --tags GIP-0088:issuance-connect')
  env.showMessage('    --tags GIP-0088:issuance-allocate')
  env.showMessage('  Optional:')
  env.showMessage('    --tags GIP-0088:issuance-close-guard')

  showPendingGovernanceTxs(env)
  env.showMessage('')
})

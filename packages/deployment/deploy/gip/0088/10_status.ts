import {
  IISSUANCE_TARGET_INTERFACE_ID,
  IREWARDS_MANAGER_INTERFACE_ID,
  ISSUANCE_TARGET_ABI,
  PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
  REWARDS_MANAGER_ABI,
  SUBGRAPH_SERVICE_CLOSE_GUARD_ABI,
} from '@graphprotocol/deployment/lib/abis.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import {
  addressEquals,
  isRewardsManagerUpgraded,
  supportsInterface,
} from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts, type RegistryEntry } from '@graphprotocol/deployment/lib/contract-registry.js'
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
  // Sync the contracts this status touches via env.getOrNull so the read paths
  // work without depending on a separate global sync run.
  await syncComponentsFromRegistry(env, [
    Contracts.horizon.RewardsManager,
    Contracts.horizon.L2GraphToken,
    Contracts['subgraph-service'].SubgraphService,
    Contracts.issuance.IssuanceAllocator,
    Contracts.issuance.RewardsEligibilityOracleA,
    Contracts.issuance.RecurringAgreementManager,
  ])

  const client = graph.getPublicClient(env) as PublicClient
  const targetChainId = await getTargetChainIdFromEnv(env)

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
    const ab =
      contract.addressBook === 'subgraph-service'
        ? graph.getSubgraphServiceAddressBook(targetChainId)
        : graph.getHorizonAddressBook(targetChainId)

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
  await showDetailedComponentStatus(env, Contracts.issuance.RewardsEligibilityOracleA, { showHints: false })

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

  // eligibility-integrate: RM.providerEligibilityOracle == REO_A
  if (rm) {
    const upgraded = await isRewardsManagerUpgraded(client, rm.address)
    if (upgraded) {
      const reo = env.getOrNull(Contracts.issuance.RewardsEligibilityOracleA.name)
      const currentOracle = (await client.readContract({
        address: rm.address as `0x${string}`,
        abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
        functionName: 'getProviderEligibilityOracle',
      })) as string

      if (reo) {
        const integrated = addressEquals(currentOracle, reo.address)
        env.showMessage(`  ${integrated ? '✓' : '✗'} eligibility-integrate: RM.providerEligibilityOracle == REO_A`)
      } else {
        env.showMessage(`  ○ eligibility-integrate: REO_A not deployed`)
      }

      // issuance-connect: RM.issuanceAllocator == IA + minter role
      const ia = env.getOrNull('IssuanceAllocator')
      if (ia) {
        const currentIA = (await client.readContract({
          address: rm.address as `0x${string}`,
          abi: ISSUANCE_TARGET_ABI,
          functionName: 'getIssuanceAllocator',
        })) as string
        const iaConnected = addressEquals(currentIA, ia.address)

        const gt = env.getOrNull('L2GraphToken')
        let isMinter = false
        if (gt) {
          const { GRAPH_TOKEN_ABI } = await import('@graphprotocol/deployment/lib/abis.js')
          isMinter = (await client.readContract({
            address: gt.address as `0x${string}`,
            abi: GRAPH_TOKEN_ABI,
            functionName: 'isMinter',
            args: [ia.address as `0x${string}`],
          })) as boolean
        }

        env.showMessage(
          `  ${iaConnected && isMinter ? '✓' : '✗'} issuance-connect: RM ↔ IA${!iaConnected ? ' (not connected)' : ''}${!isMinter ? ' (no minter role)' : ''}`,
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

  // eligibility-revert
  if (rm) {
    const supportsLatestRM = await supportsInterface(client, rm.address, IREWARDS_MANAGER_INTERFACE_ID)
    if (supportsLatestRM) {
      const revertOnIneligible = (await client.readContract({
        address: rm.address as `0x${string}`,
        abi: REWARDS_MANAGER_ABI,
        functionName: 'getRevertOnIneligible',
      })) as boolean
      env.showMessage(
        `  ${revertOnIneligible ? '✓' : '○'} eligibility-revert: revertOnIneligible = ${revertOnIneligible}`,
      )
    } else {
      env.showMessage(`  ○ eligibility-revert: RM not upgraded`)
    }
  } else {
    env.showMessage(`  ○ eligibility-revert: RM not deployed`)
  }

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
  env.showMessage('    --tags GIP-0088:eligibility-revert')
  env.showMessage('    --tags GIP-0088:issuance-close-guard')

  showPendingGovernanceTxs(env)
  env.showMessage('')
})

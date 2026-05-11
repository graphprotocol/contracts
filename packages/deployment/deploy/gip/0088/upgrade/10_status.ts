import { IISSUANCE_TARGET_INTERFACE_ID } from '@graphprotocol/deployment/lib/abis.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import { checkConfigurationStatus } from '@graphprotocol/deployment/lib/apply-configuration.js'
import {
  getREOConditions,
  getREOTransferGovernanceConditions,
  isRewardsManagerUpgraded,
} from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts, type RegistryEntry } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { getResolvedSettingsForEnv } from '@graphprotocol/deployment/lib/deployment-config.js'
import { ComponentTags, GoalTags, noTagsRequested } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { getDeployer, getProxyAdminAddress } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import {
  checkDefaultAllocationConfigured,
  checkDeployerRevoked,
  checkIAConfigured,
  checkProxyAdminTransferred,
  checkRAMConfigured,
  checkReclaimRMIntegration,
  checkReclaimRoles,
  checkRMRevertOnIneligible,
} from '@graphprotocol/deployment/lib/preconditions.js'
import { showDetailedComponentStatus, showPendingGovernanceTxs } from '@graphprotocol/deployment/lib/status-detail.js'
import { checkAllProxyStates, getContractStatusLine, runFullSync } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

/**
 * GIP-0088:upgrade status — full deployment state with next-step guidance
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:upgrade --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (noTagsRequested()) return

  // The upgrade status reads every contract in every address book — easier to
  // run a full sync than to enumerate them.
  await runFullSync(env)

  const client = graph.getPublicClient(env) as PublicClient
  const targetChainId = await getTargetChainIdFromEnv(env)

  env.showMessage('\n========== GIP-0088 Upgrade ==========')

  // --- Proxy upgrades ---
  env.showMessage('\nProxy upgrades:')

  const upgradeContracts: RegistryEntry[] = [
    Contracts.horizon.RewardsManager,
    Contracts.horizon.HorizonStaking,
    Contracts['subgraph-service'].SubgraphService,
    Contracts['subgraph-service'].DisputeManager,
    Contracts.horizon.PaymentsEscrow,
    Contracts.horizon.L2Curation,
  ]

  const rm = env.getOrNull('RewardsManager')

  for (const contract of upgradeContracts) {
    const ab =
      contract.addressBook === 'subgraph-service'
        ? graph.getSubgraphServiceAddressBook(targetChainId)
        : graph.getHorizonAddressBook(targetChainId)

    const result = await getContractStatusLine(client, contract.addressBook, ab, contract.name)
    env.showMessage(`  ${result.line}`)

    if (contract === Contracts.horizon.RewardsManager && result.exists && rm) {
      const upgraded = await isRewardsManagerUpgraded(client, rm.address)
      env.showMessage(`        ${upgraded ? '✓' : '✗'} implements IIssuanceTarget (${IISSUANCE_TARGET_INTERFACE_ID})`)
    }
  }

  const { anyCodeChanged, anyPending } = checkAllProxyStates(targetChainId)

  // --- New contracts ---
  env.showMessage('\nNew contracts:')
  await showDetailedComponentStatus(env, Contracts.horizon.RecurringCollector, { showHints: false })
  await showDetailedComponentStatus(env, Contracts.issuance.IssuanceAllocator, { showHints: false })
  await showDetailedComponentStatus(env, Contracts.issuance.DefaultAllocation, { showHints: false })
  await showDetailedComponentStatus(env, Contracts.issuance.RecurringAgreementManager, { showHints: false })
  await showDetailedComponentStatus(env, Contracts.issuance.ReclaimedRewards, { showHints: false })
  await showDetailedComponentStatus(env, Contracts.issuance.RewardsEligibilityOracleA, { showHints: false })

  // --- Next step ---
  // Uses the same precondition checks as the action scripts (shared code, not copies)
  const ia = env.getOrNull('IssuanceAllocator')
  const da = env.getOrNull('DefaultAllocation')
  const reoA = env.getOrNull('RewardsEligibilityOracleA')
  const reoB = env.getOrNull('RewardsEligibilityOracleB')
  const ram = env.getOrNull('RecurringAgreementManager')
  const reclaim = env.getOrNull('ReclaimedRewards')
  const rc = env.getOrNull('RecurringCollector')
  const ss = env.getOrNull('SubgraphService')

  const anyNewContractMissing = !ia || !da || !reoA || !reoB || !ram || !reclaim

  if (anyNewContractMissing || !rm || (anyCodeChanged && !anyPending)) {
    env.showMessage(`\n  → Next: --tags GIP-0088:upgrade,deploy`)
    const missing = [
      !ia && 'IssuanceAllocator',
      !da && 'DefaultAllocation',
      !reoA && 'REO-A',
      !reoB && 'REO-B',
      !ram && 'RAM',
      !reclaim && 'Reclaim',
      !rm && 'RM',
    ].filter(Boolean)
    if (missing.length > 0) env.showMessage(`    Missing: ${missing.join(', ')}`)
    if (anyCodeChanged && !anyPending) env.showMessage(`    Code changed without pending implementation`)
  } else {
    const governor = await getGovernor(env)
    const pauseGuardian = await getPauseGuardian(env)

    // Deployer address: from namedAccounts when key is loaded, otherwise infer
    // from ProxyAdmin owner — if not governor, it's the deployer.
    let deployer = getDeployer(env)
    if (!deployer) {
      try {
        const proxyAdminAddr = await getProxyAdminAddress(client, ia.address)
        const owner = (await client.readContract({
          address: proxyAdminAddr as `0x${string}`,
          abi: [
            { inputs: [], name: 'owner', outputs: [{ type: 'address' }], stateMutability: 'view', type: 'function' },
          ],
          functionName: 'owner',
        })) as string
        if (owner.toLowerCase() !== governor.toLowerCase()) deployer = owner
      } catch {
        // ProxyAdmin not readable — deployer stays undefined
      }
    }

    // Check configure state
    // When deployer is available, classify issues as deployer-fixable vs deferred.
    // When not (status-only run without deploy key), all issues are unclassified.
    const configIssues: string[] = []
    const deferredIssues: string[] = []

    // Helper: check if deployer has GOVERNOR_ROLE on a contract
    // Returns false when deployer is not configured (status-only run without deploy key)
    async function deployerHasGovernorRole(contractAddress: string): Promise<boolean> {
      if (!deployer) return false
      try {
        const role = (await client.readContract({
          address: contractAddress as `0x${string}`,
          abi: [
            {
              inputs: [],
              name: 'GOVERNOR_ROLE',
              outputs: [{ type: 'bytes32' }],
              stateMutability: 'view',
              type: 'function',
            },
          ],
          functionName: 'GOVERNOR_ROLE',
        })) as `0x${string}`
        return (await client.readContract({
          address: contractAddress as `0x${string}`,
          abi: [
            {
              inputs: [{ type: 'bytes32' }, { type: 'address' }],
              name: 'hasRole',
              outputs: [{ type: 'bool' }],
              stateMutability: 'view',
              type: 'function',
            },
          ],
          functionName: 'hasRole',
          args: [role, deployer as `0x${string}`],
        })) as boolean
      } catch {
        return false
      }
    }

    // Helper: classify a failing config check
    async function classifyConfigIssue(label: string, reason: string, contractAddress: string): Promise<void> {
      if (await deployerHasGovernorRole(contractAddress)) {
        configIssues.push(`${label}: ${reason}`)
      } else {
        deferredIssues.push(`${label}: ${reason}`)
      }
    }

    // Check each new contract
    const iaConfig = await checkIAConfigured(client, ia.address, rm.address, governor, pauseGuardian)
    if (!iaConfig.done && iaConfig.reason !== 'RM.issuancePerBlock is 0') {
      await classifyConfigIssue('IA', iaConfig.reason!, ia.address)
    }

    const daConfig = await checkDefaultAllocationConfigured(client, da.address, governor, pauseGuardian)
    if (!daConfig.done) {
      await classifyConfigIssue('DA', daConfig.reason!, da.address)
    }

    if (rc && ss) {
      const ramConfig = await checkRAMConfigured(
        client,
        ram.address,
        rc.address,
        ss.address,
        ia.address,
        governor,
        pauseGuardian,
      )
      if (!ramConfig.done) {
        await classifyConfigIssue('RAM', ramConfig.reason!, ram.address)
      }
    }

    const reclaimRolesCheck = await checkReclaimRoles(client, reclaim.address, governor, pauseGuardian)
    if (!reclaimRolesCheck.done) {
      await classifyConfigIssue('Reclaim', reclaimRolesCheck.reason!, reclaim.address)
    }

    // RM.setDefaultReclaimAddress — governance-only (target is RM, not Reclaim).
    // Always deferred to the upgrade governance batch, never blocks configure/transfer.
    const reclaimRMCheck = await checkReclaimRMIntegration(client, rm.address, reclaim.address)
    if (!reclaimRMCheck.done && reclaimRMCheck.reason !== 'RM not upgraded') {
      deferredIssues.push(`Reclaim: ${reclaimRMCheck.reason}`)
    }

    // RM.setRevertOnIneligible — config-driven; same deferred-only treatment as
    // setDefaultReclaimAddress (target is RM, governance-only setter).
    const settings = await getResolvedSettingsForEnv(env)
    const revertCheck = await checkRMRevertOnIneligible(client, rm.address, settings.rewardsManager.revertOnIneligible)
    if (!revertCheck.done && revertCheck.reason !== 'RM not upgraded') {
      deferredIssues.push(`RM: ${revertCheck.reason}`)
    }

    // REO configure
    const issuanceBook = graph.getIssuanceAddressBook(targetChainId)
    const hasNetworkOperator = issuanceBook.entryExists('NetworkOperator')
    if (hasNetworkOperator) {
      const reoConditions = await getREOConditions(env)
      for (const [label, addr] of [
        ['REO-A', reoA.address],
        ['REO-B', reoB.address],
      ] as const) {
        const reoConfig = await checkConfigurationStatus(client, addr, reoConditions)
        if (!reoConfig.allOk) {
          const failing = reoConfig.conditions.filter((c) => !c.ok).map((c) => c.name)
          await classifyConfigIssue(label, failing.join(', '), addr)
        }
      }
    } else {
      deferredIssues.push('NetworkOperator not configured')
    }

    const anyConfigIssues = configIssues.length > 0 || deferredIssues.length > 0

    // Check transfer state
    // ProxyAdmin ownership is deployer-independent (checks owner vs governor).
    // Deployer GOVERNOR_ROLE revocation needs the deployer address — checked
    // when available, skipped otherwise (ProxyAdmin transfer is the primary signal).
    let proxyAdminsTransferred = true

    for (const contract of [ia, da, ram, reclaim, reoA, reoB]) {
      try {
        const proxyAdminAddr = await getProxyAdminAddress(client, contract.address)
        const paCheck = await checkProxyAdminTransferred(client, proxyAdminAddr, governor)
        if (!paCheck.done) proxyAdminsTransferred = false
      } catch {
        // ProxyAdmin not readable — skip
      }
    }

    let deployerRolesRevoked = true
    if (deployer) {
      for (const contract of [ia, da, ram, reclaim]) {
        const revoked = await checkDeployerRevoked(client, contract.address, deployer)
        if (!revoked.done) deployerRolesRevoked = false
      }
      if (hasNetworkOperator) {
        const reoTransferConds = getREOTransferGovernanceConditions(deployer)
        const reoATransfer = await checkConfigurationStatus(client, reoA.address, reoTransferConds)
        if (!reoATransfer.allOk) deployerRolesRevoked = false
        const reoBTransfer = await checkConfigurationStatus(client, reoB.address, reoTransferConds)
        if (!reoBTransfer.allOk) deployerRolesRevoked = false
      }
    }

    const needsTransfer = !proxyAdminsTransferred || !deployerRolesRevoked

    // Next-step guidance
    // Lifecycle: deploy → configure → transfer → upgrade
    // ProxyAdmin not transferred ⇒ deployer still has control ⇒ configure/transfer phase
    // ProxyAdmin transferred ⇒ remaining issues need governance ⇒ upgrade phase
    if (anyConfigIssues && !proxyAdminsTransferred) {
      env.showMessage(`\n  → Next: --tags GIP-0088:upgrade,configure`)
      for (const issue of configIssues) env.showMessage(`    ${issue}`)
      if (deferredIssues.length > 0) {
        env.showMessage(`    Deferred (governance TX):`)
        for (const issue of deferredIssues) env.showMessage(`      ${issue}`)
      }
    } else if (needsTransfer) {
      env.showMessage(`\n  → Next: --tags GIP-0088:upgrade,transfer`)
    } else if (anyPending || anyConfigIssues) {
      env.showMessage(`\n  → Next: --tags GIP-0088:upgrade,upgrade`)
      if (deferredIssues.length > 0) {
        env.showMessage(`    Deferred config (governance TX):`)
        for (const issue of deferredIssues) env.showMessage(`      ${issue}`)
      }
    }
  }

  showPendingGovernanceTxs(env)
  env.showMessage(`\n  Actions: --tags GIP-0088:upgrade,<deploy|configure|transfer|upgrade>`)
  env.showMessage('')
}

func.tags = [GoalTags.GIP_0088_UPGRADE]
func.dependencies = [
  // Upgrade contracts
  ComponentTags.RECURRING_COLLECTOR,
  ComponentTags.REWARDS_MANAGER,
  ComponentTags.HORIZON_STAKING,
  ComponentTags.SUBGRAPH_SERVICE,
  ComponentTags.DISPUTE_MANAGER,
  ComponentTags.PAYMENTS_ESCROW,
  ComponentTags.L2_CURATION,
  // New contracts (shown in status)
  ComponentTags.ISSUANCE_ALLOCATOR,
  ComponentTags.DEFAULT_ALLOCATION,
  ComponentTags.RECURRING_AGREEMENT_MANAGER,
  ComponentTags.REWARDS_ELIGIBILITY_A,
]
func.skip = async () => noTagsRequested()

export default func

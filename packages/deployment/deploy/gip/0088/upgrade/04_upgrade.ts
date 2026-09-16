import {
  ACCESS_CONTROL_ENUMERABLE_ABI,
  ISSUANCE_ALLOCATOR_ABI,
  ISSUANCE_TARGET_ABI,
  RECURRING_COLLECTOR_PAUSE_ABI,
  REWARDS_MANAGER_ABI,
  REWARDS_MANAGER_DEPRECATED_ABI,
} from '@graphprotocol/deployment/lib/abis.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import { checkConfigurationStatus } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { getREOConditions } from '@graphprotocol/deployment/lib/contract-checks.js'
import { allUpgradeableEntries, Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { getResolvedSettingsForEnv, type ResolvedSettings } from '@graphprotocol/deployment/lib/deployment-config.js'
import { DeploymentActions, GoalTags, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  createGovernanceTxBuilder,
  executeTxBatchDirect,
  getGovernanceTxDir,
  saveGovernanceTx,
} from '@graphprotocol/deployment/lib/execute-governance.js'
import { formatGRT } from '@graphprotocol/deployment/lib/format.js'
import { gatherBundles, markIncorporated } from '@graphprotocol/deployment/lib/gather-bundles.js'
import {
  checkDefaultAllocationConfigured,
  checkIAConfigured,
  checkRAMConfigured,
  checkReclaimRMIntegration,
  checkReclaimRoles,
  checkRMRevertOnIneligible,
} from '@graphprotocol/deployment/lib/preconditions.js'
import { runFullSync } from '@graphprotocol/deployment/lib/sync-utils.js'
import type { TxBuilder } from '@graphprotocol/deployment/lib/tx-builder.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule, Environment } from '@rocketh/core/types'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

const GIP_0088_UPGRADES_BATCH = 'gip-0088-upgrades'

/**
 * GIP-0088:upgrade — Build the governance batch
 *
 * Single goal: assemble one TX batch that advances the deployment past the
 * governance boundary. The batch contains three groups, each of which skips
 * items already on-chain:
 *
 *   1. Proxy upgrades   — every deployable proxy with a pendingImplementation
 *   2. Existing-contract config — RC.setPauseGuardian, RM.setDefaultReclaimAddress
 *   3. Deferred new-contract config — IA/DA/RAM/Reclaim/REO role grants and
 *      params that the deployer couldn't perform (no GOVERNOR_ROLE) or that
 *      depend on RM being upgraded
 *
 * Each helper takes the builder, adds zero or more TXs, and returns the count
 * it added. The orchestrator just sums them, prints the result, and either
 * executes or saves the batch.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:upgrade,upgrade --network <network>
 *   pnpm hardhat deploy:execute-governance --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.UPGRADE)) return

  // The orchestration batch reads every deployable contract across all three
  // address books, so we need a full sync first rather than a per-component one.
  await runFullSync(env)

  const targetChainId = await getTargetChainIdFromEnv(env)
  const { governor, canSign } = await canSignAsGovernor(env)
  const pauseGuardian = await getPauseGuardian(env)
  const client = graph.getPublicClient(env) as PublicClient

  env.showMessage('\n========== GIP-0088 Upgrade: Proxy Upgrades ==========\n')

  const txDir = getGovernanceTxDir(env.name)
  const builder = await createGovernanceTxBuilder(env, GIP_0088_UPGRADES_BATCH, {
    name: 'GIP-0088 Proxy Upgrades',
    description: 'Upgrade all proxy contracts with pending implementations',
  })

  const gathered = gatherProxyUpgrades(txDir, builder)

  const settings = await getResolvedSettingsForEnv(env)

  // RM-dependent config (setDefaultReclaimAddress / setRevertOnIneligible) can only
  // run once RM is on its new implementation. If the RM upgrade is part of THIS batch,
  // it executes (ordered before these config TXs) within the same atomic governance
  // execution, so include them in the same bundle rather than deferring to a second
  // governance round.
  const rmUpgradeInBatch = gathered.sourceNames.some((n) => n.includes(Contracts.horizon.RewardsManager.name))

  env.showMessage('\nOutstanding configuration:')
  const existingCount = await collectExistingContractConfig(
    env,
    builder,
    client,
    pauseGuardian,
    settings,
    rmUpgradeInBatch,
  )
  const newCount = await collectDeferredNewContractConfig(env, builder, client, targetChainId, governor, pauseGuardian)

  const total = gathered.txCount + existingCount + newCount
  if (total === 0) {
    env.showMessage('  No pending upgrades found\n')
    return
  }

  // Record gather provenance on the builder so the on-disk bundle carries an
  // audit trail of which source files contributed. Set before save.
  builder.markGatheredFrom(gathered.sourceNames)

  if (canSign) {
    env.showMessage('\n🔨 Executing upgrade TX batch...\n')
    await executeTxBatchDirect(env, builder, governor)
    env.showMessage('\n✅ GIP-0088 Upgrade: All proxy upgrades executed\n')
  } else {
    saveGovernanceTx(env, builder, 'GIP-0088 Proxy Upgrades')
  }

  // Move the per-component source bundles into incorporated/ in both branches:
  // canSign replayed them via the consolidated batch, !canSign queued them as
  // the consolidated batch. Either way, leaving them at top level would let a
  // subsequent execute-governance run replay the same TXs again.
  markIncorporated(txDir, gathered.sourceFiles, GIP_0088_UPGRADES_BATCH)
}

func.tags = [GoalTags.GIP_0088_UPGRADE]
func.skip = async () => shouldSkipAction(DeploymentActions.UPGRADE)

export default func

// ============================================================================
// Group 1 — Proxy upgrades
// ============================================================================

/**
 * Gather per-component proxy upgrade bundles into the shared consolidated
 * builder.
 *
 * The TX-construction work is owned by each component's `02_upgrade.ts`,
 * which has already run before this orchestrator (file-system numeric order
 * `02_*` before `04_*`) and either written `txs/upgrade-<Name>.json` or not,
 * depending on whether its proxy needs an upgrade right now. This function
 * just reads whichever files are present in registry order and appends their
 * TXs (with metadata) into the consolidated builder.
 *
 * The per-component scripts and this orchestrator both flow through the same
 * `upgradeImplementation` → `buildUpgradeTxs` primitive — there is no
 * duplication of TX-construction logic. The orchestrator's role is purely to
 * consolidate.
 */
function gatherProxyUpgrades(txDir: string, builder: TxBuilder) {
  const names = Array.from(allUpgradeableEntries(), (e) => e.name)
  return gatherBundles(txDir, builder, names, 'upgrade')
}

// ============================================================================
// Group 2 — Existing contract config (RC, RM)
// ============================================================================

/**
 * Bundle the few governance-only configure items on contracts that already
 * existed before this deployment (typically the deployer does not hold
 * GOVERNOR_ROLE on them — true on networks where RM was deployed by separate
 * horizon-Ignition infrastructure; the dynamic role check is the source of truth):
 *
 *   - RC.setPauseGuardian
 *   - RM.setDefaultReclaimAddress (when RM is upgraded, or its upgrade is in this batch)
 *   - RM.setRevertOnIneligible (driven by config; same RM-upgrade gating)
 */
async function collectExistingContractConfig(
  env: Environment,
  builder: TxBuilder,
  client: PublicClient,
  pauseGuardian: string,
  settings: ResolvedSettings,
  rmUpgradeInBatch: boolean,
): Promise<number> {
  let added = 0

  // RC.setPauseGuardian
  const rc = env.getOrNull(Contracts.horizon.RecurringCollector.name)
  if (rc) {
    const isGuardian = (await client.readContract({
      address: rc.address as `0x${string}`,
      abi: RECURRING_COLLECTOR_PAUSE_ABI,
      functionName: 'pauseGuardians',
      args: [pauseGuardian as `0x${string}`],
    })) as boolean
    if (!isGuardian) {
      builder.addTx({
        to: rc.address,
        value: '0',
        data: encodeFunctionData({
          abi: RECURRING_COLLECTOR_PAUSE_ABI,
          functionName: 'setPauseGuardian',
          args: [pauseGuardian as `0x${string}`, true],
        }),
      })
      env.showMessage(`  + ${Contracts.horizon.RecurringCollector.name}.setPauseGuardian(${pauseGuardian})`)
      added++
    }
  }

  // RM.setDefaultReclaimAddress — only after RM upgrade lands in the same batch
  const reclaim = env.getOrNull(Contracts.issuance.ReclaimedRewards.name)
  const rm = env.getOrNull(Contracts.horizon.RewardsManager.name)
  if (reclaim && rm) {
    const reclaimRMCheck = await checkReclaimRMIntegration(client, rm.address, reclaim.address)
    if (!reclaimRMCheck.done && (reclaimRMCheck.reason !== 'RM not upgraded' || rmUpgradeInBatch)) {
      builder.addTx({
        to: rm.address,
        value: '0',
        data: encodeFunctionData({
          abi: REWARDS_MANAGER_ABI,
          functionName: 'setDefaultReclaimAddress',
          args: [reclaim.address as `0x${string}`],
        }),
      })
      env.showMessage(`  + ${Contracts.horizon.RewardsManager.name}.setDefaultReclaimAddress(${reclaim.address})`)
      added++
    }
  }

  // RM.setRevertOnIneligible — driven by config; only after RM upgrade lands
  if (rm) {
    const desiredRevert = settings.rewardsManager.revertOnIneligible
    const revertCheck = await checkRMRevertOnIneligible(client, rm.address, desiredRevert)
    if (!revertCheck.done && (revertCheck.reason !== 'RM not upgraded' || rmUpgradeInBatch)) {
      builder.addTx({
        to: rm.address,
        value: '0',
        data: encodeFunctionData({
          abi: REWARDS_MANAGER_ABI,
          functionName: 'setRevertOnIneligible',
          args: [desiredRevert],
        }),
      })
      env.showMessage(`  + ${Contracts.horizon.RewardsManager.name}.setRevertOnIneligible(${desiredRevert})`)
      added++
    }
  }

  return added
}

// ============================================================================
// Group 3 — Deferred new-contract config (IA, DA, RAM, Reclaim, REO A/B)
// ============================================================================

/**
 * Bundle the configure items on new contracts that the deployer couldn't
 * perform during `02_configure` because it lacks `GOVERNOR_ROLE` on the
 * proxy (typical when forking an existing deployment whose proxies were
 * already transferred).
 */
async function collectDeferredNewContractConfig(
  env: Environment,
  builder: TxBuilder,
  client: PublicClient,
  targetChainId: number,
  governor: string,
  pauseGuardian: string,
): Promise<number> {
  const grantHelper = createRoleGrantHelper(env, builder, client)
  let added = 0

  // IA: rate + roles
  const ia = env.getOrNull(Contracts.issuance.IssuanceAllocator.name)
  const rm = env.getOrNull(Contracts.horizon.RewardsManager.name)
  if (ia && rm) {
    const iaCheck = await checkIAConfigured(client, ia.address, rm.address, governor, pauseGuardian)
    if (!iaCheck.done && iaCheck.reason !== 'RM.issuancePerBlock is 0') {
      const rmRate = (await client.readContract({
        address: rm.address as `0x${string}`,
        abi: REWARDS_MANAGER_DEPRECATED_ABI,
        functionName: 'issuancePerBlock',
      })) as bigint
      const iaRate = (await client.readContract({
        address: ia.address as `0x${string}`,
        abi: ISSUANCE_ALLOCATOR_ABI,
        functionName: 'getIssuancePerBlock',
      })) as bigint
      // The outer iaCheck already returns when RM rate is 0, so rmRate > 0n here.
      if (iaRate !== rmRate) {
        builder.addTx({
          to: ia.address,
          value: '0',
          data: encodeFunctionData({
            abi: ISSUANCE_ALLOCATOR_ABI,
            functionName: 'setIssuancePerBlock',
            args: [rmRate],
          }),
        })
        env.showMessage(`  + IA.setIssuancePerBlock(${formatGRT(rmRate)})`)
        added++
      }
      added += await grantHelper(ia.address, 'IA', 'GOVERNOR_ROLE', governor, 'governor')
      added += await grantHelper(ia.address, 'IA', 'PAUSE_ROLE', pauseGuardian, 'pauseGuardian')
    }
  }

  // DA: roles
  const da = env.getOrNull(Contracts.issuance.DefaultAllocation.name)
  if (da) {
    const daCheck = await checkDefaultAllocationConfigured(client, da.address, governor, pauseGuardian)
    if (!daCheck.done) {
      added += await grantHelper(da.address, 'DA', 'GOVERNOR_ROLE', governor, 'governor')
      added += await grantHelper(da.address, 'DA', 'PAUSE_ROLE', pauseGuardian, 'pauseGuardian')
    }
  }

  // RAM: roles + setIssuanceAllocator
  const ram = env.getOrNull(Contracts.issuance.RecurringAgreementManager.name)
  const rcDep = env.getOrNull(Contracts.horizon.RecurringCollector.name)
  const ss = env.getOrNull(Contracts['subgraph-service'].SubgraphService.name)
  if (ram && rcDep && ss) {
    const ramCheck = await checkRAMConfigured(
      client,
      ram.address,
      rcDep.address,
      ss.address,
      ia?.address ?? '',
      governor,
      pauseGuardian,
    )
    if (!ramCheck.done) {
      added += await grantHelper(ram.address, 'RAM', 'COLLECTOR_ROLE', rcDep.address, 'RC')
      added += await grantHelper(ram.address, 'RAM', 'DATA_SERVICE_ROLE', ss.address, 'SS')
      added += await grantHelper(ram.address, 'RAM', 'GOVERNOR_ROLE', governor, 'governor')
      added += await grantHelper(ram.address, 'RAM', 'PAUSE_ROLE', pauseGuardian, 'pauseGuardian')
      if (ia) {
        try {
          const currentIA = (await client.readContract({
            address: ram.address as `0x${string}`,
            abi: ISSUANCE_TARGET_ABI,
            functionName: 'getIssuanceAllocator',
          })) as string
          if (currentIA.toLowerCase() !== ia.address.toLowerCase()) {
            builder.addTx({
              to: ram.address,
              value: '0',
              data: encodeFunctionData({
                abi: ISSUANCE_TARGET_ABI,
                functionName: 'setIssuanceAllocator',
                args: [ia.address as `0x${string}`],
              }),
            })
            env.showMessage(`  + RAM.setIssuanceAllocator(${ia.address})`)
            added++
          }
        } catch {
          /* getter not available */
        }
      }
    }
  }

  // Reclaim: roles only — RM integration is handled by collectExistingContractConfig
  const reclaim = env.getOrNull(Contracts.issuance.ReclaimedRewards.name)
  if (reclaim) {
    const reclaimRoles = await checkReclaimRoles(client, reclaim.address, governor, pauseGuardian)
    if (!reclaimRoles.done) {
      added += await grantHelper(reclaim.address, 'Reclaim', 'GOVERNOR_ROLE', governor, 'governor')
      added += await grantHelper(reclaim.address, 'Reclaim', 'PAUSE_ROLE', pauseGuardian, 'pauseGuardian')
    }
  }

  // REO A/B: params + roles. Driven by the same condition list as `04_configure`.
  const issuanceBook = graph.getIssuanceAddressBook(targetChainId)
  if (issuanceBook.entryExists('NetworkOperator')) {
    const reoConditions = await getREOConditions(env)
    for (const [label, entry] of [
      ['REO-A', Contracts.issuance.RewardsEligibilityOracleA],
      ['REO-B', Contracts.issuance.RewardsEligibilityOracleB],
    ] as const) {
      const reoDep = env.getOrNull(entry.name)
      if (!reoDep) continue
      const reoConfig = await checkConfigurationStatus(client, reoDep.address, reoConditions)
      if (reoConfig.allOk) continue
      for (let i = 0; i < reoConditions.length; i++) {
        if (reoConfig.conditions[i].ok) continue
        const cond = reoConditions[i]
        if (cond.type === 'role') {
          added += await grantHelper(reoDep.address, label, cond.roleGetter, cond.targetAccount, cond.description)
        } else {
          builder.addTx({
            to: reoDep.address,
            value: '0',
            data: encodeFunctionData({
              abi: cond.abi as readonly unknown[],
              functionName: cond.setter,
              args: [cond.target],
            }),
          })
          env.showMessage(`  + ${label}.${cond.setter}(${cond.target})`)
          added++
        }
      }
    }
  }

  return added
}

/**
 * Returns a closure that, when called, adds a `grantRole` TX if the role is
 * not already held. Returns 1 if a TX was added, 0 otherwise.
 */
function createRoleGrantHelper(env: Environment, builder: TxBuilder, client: PublicClient) {
  return async function addRoleGrantIfNeeded(
    contractAddr: string,
    contractName: string,
    roleName: string,
    account: string,
    accountLabel: string,
  ): Promise<number> {
    try {
      const role = (await client.readContract({
        address: contractAddr as `0x${string}`,
        abi: [
          { inputs: [], name: roleName, outputs: [{ type: 'bytes32' }], stateMutability: 'view', type: 'function' },
        ],
        functionName: roleName,
      })) as `0x${string}`
      const has = (await client.readContract({
        address: contractAddr as `0x${string}`,
        abi: ACCESS_CONTROL_ENUMERABLE_ABI,
        functionName: 'hasRole',
        args: [role, account as `0x${string}`],
      })) as boolean
      if (has) return 0
      builder.addTx({
        to: contractAddr,
        value: '0',
        data: encodeFunctionData({
          abi: ACCESS_CONTROL_ENUMERABLE_ABI,
          functionName: 'grantRole',
          args: [role, account as `0x${string}`],
        }),
      })
      env.showMessage(`  + ${contractName}.grantRole(${roleName}, ${accountLabel})`)
      return 1
    } catch {
      /* role getter not available — skip */
      return 0
    }
  }
}

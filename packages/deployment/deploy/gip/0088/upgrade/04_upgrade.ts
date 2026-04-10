import {
  ACCESS_CONTROL_ENUMERABLE_ABI,
  ISSUANCE_ALLOCATOR_ABI,
  ISSUANCE_TARGET_ABI,
  RECURRING_COLLECTOR_PAUSE_ABI,
  REWARDS_MANAGER_ABI,
  REWARDS_MANAGER_DEPRECATED_ABI,
} from '@graphprotocol/deployment/lib/abis.js'
import type { AnyAddressBookOps } from '@graphprotocol/deployment/lib/address-book-ops.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import { checkConfigurationStatus } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { getREOConditions } from '@graphprotocol/deployment/lib/contract-checks.js'
import {
  type AddressBookType,
  CONTRACT_REGISTRY,
  type ContractMetadata,
  Contracts,
} from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { DeploymentActions, GoalTags, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  createGovernanceTxBuilder,
  executeTxBatchDirect,
  saveGovernanceTx,
} from '@graphprotocol/deployment/lib/execute-governance.js'
import { formatGRT } from '@graphprotocol/deployment/lib/format.js'
import {
  checkDefaultAllocationConfigured,
  checkIAConfigured,
  checkRAMConfigured,
  checkReclaimRMIntegration,
  checkReclaimRoles,
} from '@graphprotocol/deployment/lib/preconditions.js'
import { runFullSync } from '@graphprotocol/deployment/lib/sync-utils.js'
import type { TxBuilder } from '@graphprotocol/deployment/lib/tx-builder.js'
import { buildUpgradeTxs } from '@graphprotocol/deployment/lib/upgrade-implementation.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule, Environment } from '@rocketh/core/types'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

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

  const builder = await createGovernanceTxBuilder(env, 'gip-0088-upgrades', {
    name: 'GIP-0088 Proxy Upgrades',
    description: 'Upgrade all proxy contracts with pending implementations',
  })

  const proxyCount = await collectProxyUpgrades(env, builder, targetChainId)

  env.showMessage('\nOutstanding configuration:')
  const existingCount = await collectExistingContractConfig(env, builder, client, pauseGuardian)
  const newCount = await collectDeferredNewContractConfig(env, builder, client, targetChainId, governor, pauseGuardian)

  const total = proxyCount + existingCount + newCount
  if (total === 0) {
    env.showMessage('  No pending upgrades found\n')
    return
  }

  if (canSign) {
    env.showMessage('\n🔨 Executing upgrade TX batch...\n')
    await executeTxBatchDirect(env, builder, governor)
    env.showMessage('\n✅ GIP-0088 Upgrade: All proxy upgrades executed\n')
  } else {
    saveGovernanceTx(env, builder, 'GIP-0088 Proxy Upgrades')
  }
}

func.tags = [GoalTags.GIP_0088_UPGRADE]
func.skip = async () => shouldSkipAction(DeploymentActions.UPGRADE)

export default func

// ============================================================================
// Group 1 — Proxy upgrades
// ============================================================================

/**
 * Iterate every deployable proxy in the registry. For each one with a
 * pendingImplementation in its address book, add the proxy upgrade TX.
 */
async function collectProxyUpgrades(env: Environment, builder: TxBuilder, targetChainId: number): Promise<number> {
  let added = 0
  const addressBooks: AddressBookType[] = ['horizon', 'subgraph-service', 'issuance']
  for (const abType of addressBooks) {
    const bookRegistry = CONTRACT_REGISTRY[abType]
    const ab: AnyAddressBookOps =
      abType === 'subgraph-service'
        ? graph.getSubgraphServiceAddressBook(targetChainId)
        : abType === 'issuance'
          ? graph.getIssuanceAddressBook(targetChainId)
          : graph.getHorizonAddressBook(targetChainId)

    for (const [name, metadata] of Object.entries(bookRegistry)) {
      const meta = metadata as ContractMetadata
      if (!meta.deployable || !meta.proxyType) continue
      if (!ab.entryExists(name)) continue
      const entry = ab.getEntry(name)

      // Skip contracts with no pending implementation unless they have a
      // shared implementation that might have changed (auto-detected by buildUpgradeTxs)
      if (!entry?.pendingImplementation?.address && !meta.sharedImplementation) continue

      // Derive implementationName from sharedImplementation (e.g. 'DirectAllocation_Implementation' → 'DirectAllocation')
      const implementationName = meta.sharedImplementation?.replace(/_Implementation$/, '')

      const result = await buildUpgradeTxs(
        env,
        {
          contractName: name,
          proxyType: meta.proxyType,
          proxyAdminName: meta.proxyAdminName,
          addressBook: abType,
          implementationName,
        },
        builder,
      )
      if (result.upgraded) added++
    }
  }
  return added
}

// ============================================================================
// Group 2 — Existing contract config (RC, RM)
// ============================================================================

/**
 * Bundle the few governance-only configure items on contracts that already
 * existed before this deployment (deployer never had GOVERNOR_ROLE on them):
 *
 *   - RC.setPauseGuardian
 *   - RM.setDefaultReclaimAddress (only when RM has been upgraded)
 */
async function collectExistingContractConfig(
  env: Environment,
  builder: TxBuilder,
  client: PublicClient,
  pauseGuardian: string,
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
    if (!reclaimRMCheck.done && reclaimRMCheck.reason !== 'RM not upgraded') {
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

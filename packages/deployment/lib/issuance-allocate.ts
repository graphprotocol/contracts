import type { Environment } from '@rocketh/core/types'
import type { PublicClient } from 'viem'
import { encodeFunctionData, keccak256, toHex } from 'viem'

import { graph, read, tx } from '../rocketh/deploy.js'
import { ACCESS_CONTROL_ENUMERABLE_ABI, SET_TARGET_ALLOCATION_ABI } from './abis.js'
import {
  checkIssuanceConnectComplete,
  getRewardsManagerRawIssuanceRate,
  type IssuanceConnectStatus,
} from './contract-checks.js'
import { allocationTargetContract, Contracts } from './contract-registry.js'
import { canSignAsGovernor } from './controller-utils.js'
import { getResolvedSettingsForEnv, type ResolvedAllocation, validateIssuanceAllocations } from './deployment-config.js'
import { assumeUpgraded } from './deployment-tags.js'
import { createGovernanceTxBuilder, executeTxBatchDirect, saveGovernanceTx } from './execute-governance.js'
import { formatGRT } from './format.js'
import { requireContracts, requireDeployer } from './issuance-deploy-utils.js'
import { syncComponentsFromRegistry } from './sync-utils.js'

/**
 * Order pending allocation changes decrease-first.
 *
 * `IssuanceAllocator` enforces `sum(explicit targets) <= issuancePerBlock` on every
 * `setTargetAllocation` (the default target absorbs the slack and cannot go negative).
 * Emitting the increases first would transiently overshoot and revert mid-batch, so
 * every decrease (negative delta) must precede every increase.
 *
 * Exported for unit testing — do NOT change the ordering it produces.
 */
export function compareAllocationDelta(a: { delta: bigint }, b: { delta: bigint }): number {
  return a.delta === b.delta ? 0 : a.delta < b.delta ? -1 : 1
}

/**
 * Whether a configured-but-undeployed allocation target can be safely skipped.
 *
 * `validateIssuanceAllocations` has already proven the config table sums to RM's
 * on-chain `issuancePerBlock`. Dropping a nonzero row from a proven-complete table
 * emits a semantically wrong batch: the rate freed by the other calls cannot reach
 * the missing target and falls through to the IssuanceAllocator default target. A
 * zero-rate entry (e.g. `RecurringAgreementManager` on Sepolia) contributes nothing
 * to the total, so its absence changes no other call.
 *
 * Exported for unit testing.
 */
export function isSkippableUndeployedTarget(alloc: { allocatorMintingRate: bigint; selfMintingRate: bigint }): boolean {
  return alloc.allocatorMintingRate + alloc.selfMintingRate === 0n
}

/** One-line error description; viem errors carry a `shortMessage` worth preferring. */
function describeError(err: unknown): string {
  if (err && typeof err === 'object' && 'shortMessage' in err && typeof err.shortMessage === 'string') {
    return err.shortMessage
  }
  return err instanceof Error ? err.message : String(err)
}

function reportIssuanceConnectFailure(env: Environment, goalLabel: string, failures: string[]): void {
  env.showMessage(`\n❌ ${goalLabel}: GIP-0088 issuance-connect not complete:`)
  for (const f of failures) env.showMessage(`   - ${f}`)
  env.showMessage(
    `\n   Without issuance-connect, RewardsManager is not an IssuanceAllocator target — the generated batch`,
  )
  env.showMessage(`   would order the calls wrongly and revert, potentially stranding protocol issuance.`)
  env.showMessage(`\n   Next: pnpm hardhat deploy --tags GIP-0088:issuance-connect --network ${env.name}`)
  env.showMessage(
    `   Or, for single-session sequenced bundle generation only: GIP_0088_ASSUME_UPGRADED=1 (see docs/Gip0088Runbook.md)\n`,
  )
}

function describeIncompleteConnect(connect: IssuanceConnectStatus): string[] {
  const failures: string[] = []
  if (!connect.iaIntegrated)
    failures.push(`IA not integrated with RM (current allocator: ${connect.currentIssuanceAllocator})`)
  if (!connect.iaMinter) failures.push('IA missing minter role')
  if (!connect.ratesAligned)
    failures.push(`IA/RM rate mismatch: IA=${formatGRT(connect.iaRate)}, RM=${formatGRT(connect.rmRate)}`)
  if (!connect.rmAllocationShape)
    failures.push(
      `RM allocation shape wrong: self=${formatGRT(connect.rmAllocation.selfMintingRate)}, allocator=${formatGRT(connect.rmAllocation.allocatorMintingRate)} (expected self>0, allocator=0)`,
    )
  if (!connect.fullyAllocated)
    failures.push(`IA not 100% allocated: ${formatGRT(connect.iaTotalAllocationRate)} of ${formatGRT(connect.iaRate)}`)
  return failures
}

/**
 * Precondition for emitting any `setTargetAllocation` batch: GIP-0088's
 * issuance-connect must already be complete on the target network.
 *
 * The decrease-first ordering below only sorts correctly once RM holds its full
 * issuance as a self-minting IssuanceAllocator allocation. Against an un-connected
 * RM, RM's configured entry is also an increase from zero, another target can sort
 * ahead of it, and that call reverts mid-batch — stranding whatever issuance the
 * earlier calls already moved.
 *
 * This is a property of setting IssuanceAllocator allocations, not of which GIP
 * invokes it, so it lives here and both GIP wrappers inherit it.
 *
 * Bypass: `GIP_0088_ASSUME_UPGRADED=1` — the existing flag for GIP-0088's
 * single-session sequenced-bundle workflow, where every bundle is generated before
 * the connect bundle executes.
 *
 * @returns true when it is safe to emit the batch
 */
async function issuanceConnectSatisfied(
  env: Environment,
  client: PublicClient,
  goalLabel: string,
  iaAddress: string,
  rmAddress: string,
  gtAddress: string,
): Promise<boolean> {
  if (assumeUpgraded()) {
    env.showMessage(`\n⚠️  GIP_0088_ASSUME_UPGRADED=1 — issuance-connect precondition BYPASSED`)
    env.showMessage(`   The batch about to be generated is SEQUENCED-ONLY: it is valid solely when executed`)
    env.showMessage(`   AFTER the GIP-0088 issuance-connect bundle, in Safe nonce order.`)
    env.showMessage(`   Executed before it — or standalone — the setTargetAllocation calls revert and can`)
    env.showMessage(`   strand protocol issuance. Do NOT use this flag for re-runs or recovery.\n`)
    return true
  }

  let connect: IssuanceConnectStatus
  try {
    connect = await checkIssuanceConnectComplete(client, iaAddress, rmAddress, gtAddress)
  } catch (err) {
    // RM.getIssuanceAllocator() reverts on a RewardsManager that isn't wired to the
    // IIssuanceTarget implementation yet — i.e. issuance-connect never ran. Any other
    // read fault surfaces here too, so the underlying error is reported verbatim.
    reportIssuanceConnectFailure(env, goalLabel, [
      `issuance-connect state unreadable — RM is likely not on the IIssuanceTarget implementation: ${describeError(err)}`,
    ])
    return false
  }

  if (!connect.complete) {
    reportIssuanceConnectFailure(env, goalLabel, describeIncompleteConnect(connect))
    return false
  }
  return true
}

/**
 * Apply the configured issuance allocation table for a given GIP goal.
 *
 * Sets `IA.setTargetAllocation(target, allocatorRate, selfRate)` for every target
 * named in `config/<network>.json5` (IssuanceAllocator.allocations, keyed by full
 * contract name) to exactly its configured rate — no rebalancing or residual
 * computation. The config is the complete, explicit distribution.
 *
 * Refuses to emit anything unless GIP-0088's issuance-connect is complete on the
 * target network (see {@link issuanceConnectSatisfied}) — the decrease-first
 * ordering is only correct once RM holds its issuance as an IA allocation.
 *
 * Errors early (before any TX) if the config total doesn't match RM's on-chain
 * issuancePerBlock, or if the per-target rates don't sum to it
 * (see validateIssuanceAllocations). The script never sets the issuance rate.
 *
 * Refuses to emit anything if a target configured at a nonzero rate is not deployed
 * (see {@link isSkippableUndeployedTarget}) — a partial batch off a proven-complete
 * table diverts the missing target's issuance to the IA default target.
 *
 * Idempotent: targets already at their configured allocation are skipped.
 */
export async function applyIssuanceAllocationTable(
  env: Environment,
  options: { batchName: string; goalLabel: string; meta?: { name?: string; description?: string } },
): Promise<void> {
  const settings = await getResolvedSettingsForEnv(env)
  if (settings.issuanceAllocator.allocations.length === 0) {
    env.showMessage('\n  ○ No issuance allocations configured — skipping\n')
    return
  }

  // Sync the IA, RM, and every configured target so reads resolve.
  const targetEntries = settings.issuanceAllocator.allocations.map((a) => allocationTargetContract(a.target))
  // Controller is needed by canSignAsGovernor further down; without it the run
  // aborts with "Controller not deployed" after all the reads have happened.
  await syncComponentsFromRegistry(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    Contracts.horizon.L2GraphToken,
    Contracts.horizon.Controller,
    ...targetEntries,
  ])

  const client = graph.getPublicClient(env) as PublicClient
  const readFn = read(env)

  const [issuanceAllocator, rewardsManager, graphToken] = requireContracts(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    Contracts.horizon.L2GraphToken,
  ])
  const ia = issuanceAllocator

  env.showMessage(`\n========== ${options.goalLabel} ==========`)
  env.showMessage(`IA: ${ia.address}`)

  // Precondition: GIP-0088 issuance-connect must be complete, or the batch would
  // be ordered wrongly and revert. Shared by every caller of this function.
  const connectOk = await issuanceConnectSatisfied(
    env,
    client,
    options.goalLabel,
    ia.address,
    rewardsManager.address,
    graphToken.address,
  )
  if (!connectOk) return

  // Validate the config table against RM's on-chain issuance rate (errors early).
  const rmIssuancePerBlock = await getRewardsManagerRawIssuanceRate(client, rewardsManager.address)
  const allocations = validateIssuanceAllocations(settings, rmIssuancePerBlock)
  env.showMessage(`Issuance per block (RM): ${formatGRT(rmIssuancePerBlock)} — config table validated\n`)

  // Resolve each target's address and read its current allocation, so we only
  // emit setTargetAllocation for targets that aren't already at config.
  type Pending = ResolvedAllocation & { address: `0x${string}`; label: string; delta: bigint }
  const pending: Pending[] = []
  const missing: string[] = []
  for (const alloc of allocations) {
    const entry = allocationTargetContract(alloc.target)
    const dep = env.getOrNull(entry.name)
    if (!dep) {
      if (isSkippableUndeployedTarget(alloc)) {
        env.showMessage(`  ○ ${alloc.target} not deployed — skipping (configured at 0)`)
      } else {
        missing.push(alloc.target)
        env.showMessage(
          `  ✗ ${alloc.target} not deployed — configured at ${formatGRT(alloc.allocatorMintingRate + alloc.selfMintingRate)}`,
        )
      }
      continue
    }
    const address = dep.address as `0x${string}`
    const current = (await readFn(ia, {
      functionName: 'getTargetAllocation',
      args: [address],
    })) as { totalAllocationRate: bigint; allocatorMintingRate: bigint; selfMintingRate: bigint }

    const newTotal = alloc.allocatorMintingRate + alloc.selfMintingRate
    const matches =
      current.allocatorMintingRate === alloc.allocatorMintingRate && current.selfMintingRate === alloc.selfMintingRate
    const label = `setTargetAllocation(${alloc.target}, ${formatGRT(alloc.allocatorMintingRate)}, ${formatGRT(alloc.selfMintingRate)})`
    env.showMessage(
      `  ${matches ? '✓' : '✗'} ${alloc.target}: on-chain allocator=${formatGRT(current.allocatorMintingRate)}, self=${formatGRT(current.selfMintingRate)}`,
    )
    if (!matches) {
      pending.push({
        ...alloc,
        address,
        label,
        delta: newTotal - (current.allocatorMintingRate + current.selfMintingRate),
      })
    }
  }

  // An undeployed target has no address, so its call is unencodable whatever the
  // execution order — this refusal is correct in the GIP_0088_ASSUME_UPGRADED
  // sequenced-bundle flow too, and deliberately not bypassable by it.
  if (missing.length > 0) {
    env.showMessage(`\n❌ ${options.goalLabel}: configured allocation target(s) not deployed: ${missing.join(', ')}`)
    env.showMessage(`   The table validated against RM's issuance rate, but that rate cannot reach them —`)
    env.showMessage(`   emitting only the remaining calls would divert it to the IA default target.`)
    env.showMessage(`   Next: deploy them first (e.g. --tags InnovationAllocation,deploy) and re-run.\n`)
    return
  }

  if (pending.length === 0) {
    env.showMessage(`\n✅ All configured allocations already match — nothing to do\n`)
    return
  }

  // The allocator enforces total == issuancePerBlock (the default target absorbs
  // slack, but can't go negative). Apply decreases before increases so the
  // explicit total never transiently exceeds issuance mid-batch.
  pending.sort(compareAllocationDelta)

  const txs = pending.map((p) => ({
    to: ia.address,
    data: encodeFunctionData({
      abi: SET_TARGET_ALLOCATION_ABI,
      functionName: 'setTargetAllocation',
      args: [p.address, p.allocatorMintingRate, p.selfMintingRate],
    }),
    label: p.label,
  }))

  // Determine executor.
  const deployer = requireDeployer(env)
  const GOVERNOR_ROLE = keccak256(toHex('GOVERNOR_ROLE'))
  let deployerIsGovernor = false
  try {
    deployerIsGovernor = (await client.readContract({
      address: ia.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [GOVERNOR_ROLE, deployer as `0x${string}`],
    })) as boolean
  } catch {
    // Storage not available (stale fork) — fall through to governor path
  }

  if (deployerIsGovernor) {
    env.showMessage('\n🔨 Executing as deployer...\n')
    const txFn = tx(env)
    for (const t of txs) {
      await txFn({ account: deployer, to: t.to, data: t.data })
      env.showMessage(`  ✓ ${t.label}`)
    }
    env.showMessage(`\n✅ ${options.goalLabel} — allocation table applied!\n`)
    return
  }

  const { governor, canSign } = await canSignAsGovernor(env)
  const builder = await createGovernanceTxBuilder(env, options.batchName, options.meta)
  for (const t of txs) {
    builder.addTx({ to: t.to, value: '0', data: t.data })
    env.showMessage(`  + ${t.label}`)
  }

  if (canSign) {
    env.showMessage('\n🔨 Executing configuration TX batch...\n')
    await executeTxBatchDirect(env, builder, governor)
    env.showMessage(`\n✅ ${options.goalLabel} — allocation table applied!\n`)
  } else {
    saveGovernanceTx(env, builder, options.goalLabel)
  }
}

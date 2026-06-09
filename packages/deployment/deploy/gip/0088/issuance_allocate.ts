import { ACCESS_CONTROL_ENUMERABLE_ABI, SET_TARGET_ALLOCATION_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { getRewardsManagerRawIssuanceRate } from '@graphprotocol/deployment/lib/contract-checks.js'
import { allocationTargetContract, Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import {
  getResolvedSettingsForEnv,
  type ResolvedAllocation,
  validateIssuanceAllocations,
} from '@graphprotocol/deployment/lib/deployment-config.js'
import { ComponentTags, GoalTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  createGovernanceTxBuilder,
  executeTxBatchDirect,
  saveGovernanceTx,
} from '@graphprotocol/deployment/lib/execute-governance.js'
import { formatGRT } from '@graphprotocol/deployment/lib/format.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph, read, tx } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'
import { encodeFunctionData, keccak256, toHex } from 'viem'

/**
 * GIP-0088:issuance-allocate — Apply the configured issuance allocation table
 *
 * Sets `IA.setTargetAllocation(target, allocatorRate, selfRate)` for every target
 * named in `config/<network>.json5` (IssuanceAllocator.allocations, keyed by full
 * contract name) to exactly its configured rate — no rebalancing or residual
 * computation. The config is the complete, explicit distribution.
 *
 * Errors early (before any TX) if the config total doesn't match RM's on-chain
 * issuancePerBlock, or if the per-target rates don't sum to it
 * (see validateIssuanceAllocations). The script never sets the issuance rate.
 *
 * Idempotent: targets already at their configured allocation are skipped.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:issuance-allocate --network <network>
 */
export default createActionModule(
  GoalTags.GIP_0088_ISSUANCE_ALLOCATE,
  async (env) => {
    const settings = await getResolvedSettingsForEnv(env)
    if (settings.issuanceAllocator.allocations.length === 0) {
      env.showMessage('\n  ○ No issuance allocations configured — skipping\n')
      return
    }

    // Sync the IA, RM, and every configured target so reads resolve.
    const targetEntries = settings.issuanceAllocator.allocations.map((a) => allocationTargetContract(a.target))
    await syncComponentsFromRegistry(env, [
      Contracts.issuance.IssuanceAllocator,
      Contracts.horizon.RewardsManager,
      ...targetEntries,
    ])

    const client = graph.getPublicClient(env) as PublicClient
    const readFn = read(env)

    const [issuanceAllocator, rewardsManager] = requireContracts(env, [
      Contracts.issuance.IssuanceAllocator,
      Contracts.horizon.RewardsManager,
    ])
    const ia = issuanceAllocator

    env.showMessage(`\n========== GIP-0088: Issuance Allocate ==========`)
    env.showMessage(`IA: ${ia.address}`)

    // Validate the config table against RM's on-chain issuance rate (errors early).
    const rmIssuancePerBlock = await getRewardsManagerRawIssuanceRate(client, rewardsManager.address)
    const allocations = validateIssuanceAllocations(settings, rmIssuancePerBlock)
    env.showMessage(`Issuance per block (RM): ${formatGRT(rmIssuancePerBlock)} — config table validated\n`)

    // Resolve each target's address and read its current allocation, so we only
    // emit setTargetAllocation for targets that aren't already at config.
    type Pending = ResolvedAllocation & { address: `0x${string}`; label: string; delta: bigint }
    const pending: Pending[] = []
    for (const alloc of allocations) {
      const entry = allocationTargetContract(alloc.target)
      const dep = env.getOrNull(entry.name)
      if (!dep) {
        env.showMessage(`  ○ ${alloc.target} not deployed — skipping its allocation`)
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

    if (pending.length === 0) {
      env.showMessage(`\n✅ All configured allocations already match — nothing to do\n`)
      return
    }

    // The allocator enforces total == issuancePerBlock (the default target absorbs
    // slack, but can't go negative). Apply decreases before increases so the
    // explicit total never transiently exceeds issuance mid-batch.
    pending.sort((a, b) => (a.delta === b.delta ? 0 : a.delta < b.delta ? -1 : 1))

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
      env.showMessage(`\n✅ GIP-0088: Issuance Allocate — allocation table applied!\n`)
      return
    }

    const { governor, canSign } = await canSignAsGovernor(env)
    const builder = await createGovernanceTxBuilder(env, `gip-0088-issuance-allocate`)
    for (const t of txs) {
      builder.addTx({ to: t.to, value: '0', data: t.data })
      env.showMessage(`  + ${t.label}`)
    }

    if (canSign) {
      env.showMessage('\n🔨 Executing configuration TX batch...\n')
      await executeTxBatchDirect(env, builder, governor)
      env.showMessage(`\n✅ GIP-0088: Issuance Allocate — allocation table applied!\n`)
    } else {
      saveGovernanceTx(env, builder, `GIP-0088: issuance-allocate`)
    }
  },
  { dependencies: [GoalTags.GIP_0088_ISSUANCE_CONNECT, ComponentTags.RECURRING_AGREEMENT_MANAGER] },
)

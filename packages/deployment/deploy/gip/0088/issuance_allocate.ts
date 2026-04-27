import { ACCESS_CONTROL_ENUMERABLE_ABI, SET_TARGET_ALLOCATION_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { loadDeploymentConfig } from '@graphprotocol/deployment/lib/deployment-config.js'
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
import { encodeFunctionData, keccak256, parseUnits, toHex } from 'viem'

/**
 * GIP-0088:issuance-allocate — Allocate issuance to Recurring Agreement Manager
 *
 * Calls setTargetAllocation(RAM, allocatorMintingRate, selfMintingRate) so IA
 * distributes minted GRT to RAM for agreement-based payments.
 *
 * Rates are read from config/<network>.json5 (committed per-chain config).
 * Skips if rate is 0 (not yet decided).
 *
 * Idempotent: checks on-chain state, skips if already configured.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:issuance-allocate --network <network>
 */
export default createActionModule(
  GoalTags.GIP_0088_ISSUANCE_ALLOCATE,
  async (env) => {
    await syncComponentsFromRegistry(env, [
      Contracts.issuance.IssuanceAllocator,
      Contracts.issuance.RecurringAgreementManager,
      Contracts.horizon.RewardsManager,
    ])

    const client = graph.getPublicClient(env) as PublicClient
    const readFn = read(env)

    const iaDep = env.getOrNull(Contracts.issuance.IssuanceAllocator.name)
    const ramDep = env.getOrNull(Contracts.issuance.RecurringAgreementManager.name)
    if (!iaDep || !ramDep) {
      const missing = [!iaDep && 'IssuanceAllocator', !ramDep && 'RecurringAgreementManager'].filter(Boolean)
      env.showMessage(`\n  ○ Skipping RAM allocation — not deployed: ${missing.join(', ')}\n`)
      return
    }
    const ia = iaDep
    const ram = ramDep

    env.showMessage(`\n========== GIP-0088: Issuance Allocate ==========`)
    env.showMessage(`IA:  ${ia.address}`)
    env.showMessage(`RAM: ${ram.address}`)

    // Load config
    const config = await loadDeploymentConfig(env)
    const iaConfig = config.IssuanceAllocator ?? {}
    const allocatorMintingRate = parseUnits(iaConfig.ramAllocatorMintingGrtPerBlock ?? '0', 18)
    const selfMintingRate = parseUnits(iaConfig.ramSelfMintingGrtPerBlock ?? '0', 18)

    if (allocatorMintingRate === 0n && selfMintingRate === 0n) {
      env.showMessage('\n⚠️  RAM allocation rates not configured (both 0).')
      env.showMessage('   Set ramAllocatorMintingGrtPerBlock in config/<network>.json5')
      env.showMessage('   Skipping RAM allocation configuration.\n')
      return
    }

    // Check current state
    env.showMessage('\n📋 Checking current configuration...\n')
    env.showMessage(
      `  Config: allocatorMintingRate=${formatGRT(allocatorMintingRate)}, selfMintingRate=${formatGRT(selfMintingRate)}`,
    )

    let currentRamAlloc = 0n
    let currentRamSelf = 0n
    let ramAllocated = false
    try {
      const allocation = (await readFn(ia, {
        functionName: 'getTargetAllocation',
        args: [ram.address],
      })) as { totalAllocationRate: bigint; allocatorMintingRate: bigint; selfMintingRate: bigint }
      currentRamAlloc = allocation.allocatorMintingRate
      currentRamSelf = allocation.selfMintingRate
      ramAllocated = currentRamAlloc === allocatorMintingRate && currentRamSelf === selfMintingRate
      env.showMessage(
        `  On-chain: allocator=${formatGRT(currentRamAlloc)}, self=${formatGRT(currentRamSelf)} ${ramAllocated ? '✓' : '✗'}`,
      )
    } catch {
      env.showMessage(`  RAM allocation: ✗ (not configured)`)
    }

    if (ramAllocated) {
      env.showMessage(`\n✅ RAM allocation already matches config\n`)
      return
    }

    // The allocator enforces a 100% invariant (sum of all targets == issuancePerBlock).
    // RewardsManager was given 100% as self-minting in issuance-connect, so we must
    // atomically rebalance: take from RM's self-minting and give to RAM, in the same batch.
    const [rewardsManager] = requireContracts(env, [Contracts.horizon.RewardsManager])
    const rmAddress = rewardsManager.address as `0x${string}`
    const rmAllocation = (await readFn(ia, {
      functionName: 'getTargetAllocation',
      args: [rmAddress],
    })) as { totalAllocationRate: bigint; allocatorMintingRate: bigint; selfMintingRate: bigint }
    env.showMessage(
      `  RM on-chain: allocator=${formatGRT(rmAllocation.allocatorMintingRate)}, self=${formatGRT(rmAllocation.selfMintingRate)}`,
    )

    const newRamTotal = allocatorMintingRate + selfMintingRate
    const currentRamTotal = currentRamAlloc + currentRamSelf
    const delta = newRamTotal - currentRamTotal // signed: >0 RAM grows, <0 RAM shrinks
    if (delta > 0n && rmAllocation.selfMintingRate < delta) {
      env.showMessage(
        `\n❌ Insufficient RM self-minting (${formatGRT(rmAllocation.selfMintingRate)}) to fund RAM increase (${formatGRT(delta)})\n`,
      )
      process.exit(1)
    }
    const newRmSelf = rmAllocation.selfMintingRate - delta

    // Determine executor
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

    const setRamData = encodeFunctionData({
      abi: SET_TARGET_ALLOCATION_ABI,
      functionName: 'setTargetAllocation',
      args: [ram.address as `0x${string}`, allocatorMintingRate, selfMintingRate],
    })
    const setRmData = encodeFunctionData({
      abi: SET_TARGET_ALLOCATION_ABI,
      functionName: 'setTargetAllocation',
      args: [rmAddress, rmAllocation.allocatorMintingRate, newRmSelf],
    })
    const ramLabel = `setTargetAllocation(RAM, ${formatGRT(allocatorMintingRate)}, ${formatGRT(selfMintingRate)})`
    const rmLabel = `setTargetAllocation(RM, ${formatGRT(rmAllocation.allocatorMintingRate)}, ${formatGRT(newRmSelf)})`

    // Order matters: free budget first, then consume.
    // delta > 0 (RAM grows): reduce RM first so default target absorbs the slack.
    // delta < 0 (RAM shrinks): reduce RAM first so default target absorbs the slack.
    const txs =
      delta > 0n
        ? [
            { data: setRmData, label: rmLabel },
            { data: setRamData, label: ramLabel },
          ]
        : [
            { data: setRamData, label: ramLabel },
            { data: setRmData, label: rmLabel },
          ]

    if (deployerIsGovernor) {
      env.showMessage('\n🔨 Executing as deployer...\n')
      const txFn = tx(env)
      for (const t of txs) {
        await txFn({ account: deployer, to: ia.address, data: t.data })
        env.showMessage(`  ✓ ${t.label}`)
      }
      env.showMessage(`\n✅ GIP-0088: Issuance Allocate — RAM allocation configured!\n`)
    } else {
      const { governor, canSign } = await canSignAsGovernor(env)

      const builder = await createGovernanceTxBuilder(env, `gip-0088-issuance-allocate`)
      for (const t of txs) {
        builder.addTx({ to: ia.address, value: '0', data: t.data })
        env.showMessage(`  + ${t.label}`)
      }

      if (canSign) {
        env.showMessage('\n🔨 Executing configuration TX batch...\n')
        await executeTxBatchDirect(env, builder, governor)
        env.showMessage(`\n✅ GIP-0088: Issuance Allocate — RAM allocation configured!\n`)
      } else {
        saveGovernanceTx(env, builder, `GIP-0088: issuance-allocate`)
      }
    }
  },
  { dependencies: [GoalTags.GIP_0088_ISSUANCE_CONNECT, ComponentTags.RECURRING_AGREEMENT_MANAGER] },
)

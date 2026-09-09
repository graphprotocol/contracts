import {
  GRAPH_TOKEN_ABI,
  ISSUANCE_ALLOCATOR_ABI,
  ISSUANCE_TARGET_ABI,
  REWARDS_MANAGER_DEPRECATED_ABI,
  SET_TARGET_ALLOCATION_ABI,
} from '@graphprotocol/deployment/lib/abis.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import {
  checkIssuanceConnectComplete,
  requireRewardsManagerUpgraded,
} from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { assumeUpgraded, ComponentTags, GoalTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  createGovernanceTxBuilder,
  executeTxBatchDirect,
  saveGovernanceTx,
} from '@graphprotocol/deployment/lib/execute-governance.js'
import { formatGRT } from '@graphprotocol/deployment/lib/format.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * GIP-0088:issuance-connect — Connect Rewards Manager to Issuance Allocator
 *
 * - Configure RewardsManager to use IssuanceAllocator
 * - Grant minter role to IssuanceAllocator on GraphToken
 *
 * Idempotent: checks on-chain state, skips if already activated.
 * If the provider has access to the governor key, executes directly.
 * Otherwise generates governance TX file.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:issuance-connect --network <network>
 */
export default createActionModule(
  GoalTags.GIP_0088_ISSUANCE_CONNECT,
  async (env) => {
    await syncComponentsFromRegistry(env, [
      Contracts.issuance.IssuanceAllocator,
      Contracts.horizon.RewardsManager,
      Contracts.horizon.L2GraphToken,
      Contracts.issuance.DefaultAllocation,
    ])

    const deployer = requireDeployer(env)

    // Check if the provider can sign as the protocol governor
    const { governor, canSign } = await canSignAsGovernor(env)

    const [issuanceAllocator, rewardsManager, graphToken, defaultAllocation] = requireContracts(env, [
      Contracts.issuance.IssuanceAllocator,
      Contracts.horizon.RewardsManager,
      Contracts.horizon.L2GraphToken,
      Contracts.issuance.DefaultAllocation,
    ])

    const iaAddress = issuanceAllocator.address
    const rmAddress = rewardsManager.address
    const gtAddress = graphToken.address
    const daAddress = defaultAllocation.address

    // Create viem client for direct contract calls
    const client = graph.getPublicClient(env) as PublicClient

    const sequenced = assumeUpgraded()

    // Check if RewardsManager supports IIssuanceTarget (has been upgraded).
    // Throws if not upgraded — skipped under sequenced generation, where this
    // bundle is built to execute right after the upgrade bundle (nonce order).
    if (!sequenced) {
      await requireRewardsManagerUpgraded(client, rmAddress, env)
    } else {
      env.showMessage(
        '\n⚠ Sequenced generation: RM upgrade assumed — this bundle is SEQUENCED-ONLY and valid only AFTER the upgrade bundle executes (nonce order).\n',
      )
    }

    const targetChainId = await getTargetChainIdFromEnv(env)

    env.showMessage(`\n========== GIP-0088: Issuance Connect ==========`)
    env.showMessage(`Network: ${env.name} (chainId=${targetChainId})`)
    env.showMessage(`Deployer: ${deployer}`)
    env.showMessage(`Protocol Governor (from Controller): ${governor}`)
    env.showMessage(`${Contracts.issuance.IssuanceAllocator.name}: ${iaAddress}`)
    env.showMessage(`${Contracts.horizon.RewardsManager.name}: ${rmAddress}`)
    env.showMessage(`${Contracts.horizon.L2GraphToken.name}: ${gtAddress}\n`)

    // Check current state via the shared issuance-connect end-state helper.
    // Sub-flags drive both the per-line status display and which TXs the build-batch needs.
    env.showMessage('📋 Checking current activation state...\n')

    // Sequenced generation: RM isn't upgraded yet, so RM.getIssuanceAllocator (the
    // iaIntegrated read inside checkIssuanceConnectComplete) would revert. Assume the
    // RM-side wiring is undone and emit it. The rate invariant below is still enforced
    // — both rates are readable on the un-upgraded RM. IA-side reads (default target)
    // stay live in the TX-build section downstream.
    const connect = sequenced
      ? {
          complete: false,
          iaIntegrated: false,
          iaMinter: false,
          rmAllocationShape: false,
          fullyAllocated: false,
          iaRate: (await client.readContract({
            address: iaAddress as `0x${string}`,
            abi: ISSUANCE_ALLOCATOR_ABI,
            functionName: 'getIssuancePerBlock',
          })) as bigint,
          rmRate: (await client.readContract({
            address: rmAddress as `0x${string}`,
            abi: REWARDS_MANAGER_DEPRECATED_ABI,
            functionName: 'issuancePerBlock',
          })) as bigint,
          get ratesAligned(): boolean {
            return this.iaRate === this.rmRate
          },
          currentIssuanceAllocator: '(unknown — RM not upgraded)',
          rmAllocation: { selfMintingRate: 0n, allocatorMintingRate: 0n },
        }
      : await checkIssuanceConnectComplete(client, iaAddress, rmAddress, gtAddress)

    env.showMessage(
      `  IA integrated: ${connect.iaIntegrated ? '✓' : '✗'} (current: ${connect.currentIssuanceAllocator})`,
    )
    env.showMessage(`  IA minter: ${connect.iaMinter ? '✓' : '✗'}`)
    env.showMessage(
      `  RM allocation: ${connect.rmAllocationShape && connect.fullyAllocated ? '✓' : '✗'} (self: ${formatGRT(connect.rmAllocation.selfMintingRate)}, allocator: ${formatGRT(connect.rmAllocation.allocatorMintingRate)})`,
    )

    if (connect.complete) {
      env.showMessage(`\n✅ RM already connected to IssuanceAllocator\n`)
      return
    }

    // Migration invariant: before wiring RM → IA, the rates must align. Once IA is
    // already integrated, downstream goals (issuance-allocate) may have intentionally
    // rebalanced part of IA's rate to other targets, so we only enforce this on the
    // initial wire-up.
    if (!connect.iaIntegrated && !connect.ratesAligned) {
      env.showMessage(
        `\n❌ Migration invariant failed: IA.issuancePerBlock (${formatGRT(connect.iaRate)}) != RM.issuancePerBlock (${formatGRT(connect.rmRate)})`,
      )
      env.showMessage(`   IA must have the same overall rate as RM before connection.\n`)
      process.exit(1)
    }
    if (!connect.iaIntegrated) {
      env.showMessage(`  Migration invariant: ✓ IA rate == RM rate (${formatGRT(connect.iaRate)})`)
    }

    // Build TX batch — order:
    //   1. IA.setTargetAllocation(RM, 0, rate)  — register RM in IA first
    //   2. RM.setIssuanceAllocator(IA)          — flip RM to read from a fully-configured IA
    //   3. GraphToken.addMinter(IA)             — grant IA the minter role
    //   4. IA.setDefaultTarget(DA)              — install safety-net default
    // Conceptually: configure IA's view of RM before RM starts reading from IA. Atomic
    // within the batch either way, but this avoids a transient where RM is wired to an
    // IA that has no allocation entry for it.
    env.showMessage('\n🔨 Building activation TX batch...\n')

    const builder = await createGovernanceTxBuilder(env, `gip-0088-issuance-connect`)

    // 1. IA.setTargetAllocation(RM, 0, rate) — RM as 100% self-minting target
    if (!connect.rmAllocationShape || !connect.fullyAllocated) {
      const data = encodeFunctionData({
        abi: SET_TARGET_ALLOCATION_ABI,
        functionName: 'setTargetAllocation',
        args: [rmAddress as `0x${string}`, 0n, connect.iaRate],
      })
      builder.addTx({ to: iaAddress, value: '0', data })
      env.showMessage(`  + IA.setTargetAllocation(RM, 0, ${formatGRT(connect.iaRate)})`)
    }

    // 2. RM.setIssuanceAllocator(IA) — RM accepts IA as its allocator
    if (!connect.iaIntegrated) {
      const data = encodeFunctionData({
        abi: ISSUANCE_TARGET_ABI,
        functionName: 'setIssuanceAllocator',
        args: [iaAddress as `0x${string}`],
      })
      builder.addTx({ to: rmAddress, value: '0', data })
      env.showMessage(`  + RewardsManager.setIssuanceAllocator(${iaAddress})`)
    }

    // 3. GraphToken.addMinter(IA) — IA needs minter role for allocator-minting
    if (!connect.iaMinter) {
      const data = encodeFunctionData({
        abi: GRAPH_TOKEN_ABI,
        functionName: 'addMinter',
        args: [iaAddress as `0x${string}`],
      })
      builder.addTx({ to: gtAddress, value: '0', data })
      env.showMessage(`  + GraphToken.addMinter(${iaAddress})`)
    }

    // 4. IA.setDefaultTarget(DA) — safety net for unallocated issuance
    let defaultTargetOk = false
    try {
      const currentDefault = (await client.readContract({
        address: iaAddress as `0x${string}`,
        abi: ISSUANCE_ALLOCATOR_ABI,
        functionName: 'getTargetAt',
        args: [0n],
      })) as string
      defaultTargetOk = currentDefault.toLowerCase() === daAddress.toLowerCase()
    } catch {
      // No targets yet
    }
    env.showMessage(`  DA default target: ${defaultTargetOk ? '✓' : '✗'}`)

    if (!defaultTargetOk) {
      const data = encodeFunctionData({
        abi: ISSUANCE_ALLOCATOR_ABI,
        functionName: 'setDefaultTarget',
        args: [daAddress as `0x${string}`],
      })
      builder.addTx({ to: iaAddress, value: '0', data })
      env.showMessage(`  + IA.setDefaultTarget(${daAddress})`)
    }

    if (canSign) {
      env.showMessage('\n🔨 Executing activation TX batch...\n')
      await executeTxBatchDirect(env, builder, governor)
      env.showMessage(`\n✅ GIP-0088: Issuance Connect — RM connected to IssuanceAllocator!\n`)
    } else {
      saveGovernanceTx(env, builder, `GIP-0088: issuance-connect`)
    }
  },
  { dependencies: [ComponentTags.ISSUANCE_ALLOCATOR, ComponentTags.DEFAULT_ALLOCATION, ComponentTags.REWARDS_MANAGER] },
)

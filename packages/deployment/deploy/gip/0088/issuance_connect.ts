import {
  GRAPH_TOKEN_ABI,
  ISSUANCE_ALLOCATOR_ABI,
  ISSUANCE_TARGET_ABI,
  REWARDS_MANAGER_DEPRECATED_ABI,
  SET_TARGET_ALLOCATION_ABI,
} from '@graphprotocol/deployment/lib/abis.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import { requireRewardsManagerUpgraded } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
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

    // Check if RewardsManager supports IIssuanceTarget (has been upgraded)
    // Throws error if not upgraded
    await requireRewardsManagerUpgraded(client, rmAddress, env)

    const targetChainId = await getTargetChainIdFromEnv(env)

    env.showMessage(`\n========== GIP-0088: Issuance Connect ==========`)
    env.showMessage(`Network: ${env.name} (chainId=${targetChainId})`)
    env.showMessage(`Deployer: ${deployer}`)
    env.showMessage(`Protocol Governor (from Controller): ${governor}`)
    env.showMessage(`${Contracts.issuance.IssuanceAllocator.name}: ${iaAddress}`)
    env.showMessage(`${Contracts.horizon.RewardsManager.name}: ${rmAddress}`)
    env.showMessage(`${Contracts.horizon.L2GraphToken.name}: ${gtAddress}\n`)

    // Check current state
    env.showMessage('📋 Checking current activation state...\n')

    const checks = {
      iaIntegrated: false,
      iaMinter: false,
    }

    // Check RM.getIssuanceAllocator() == IA
    const currentIA = (await client.readContract({
      address: rmAddress as `0x${string}`,
      abi: ISSUANCE_TARGET_ABI,
      functionName: 'getIssuanceAllocator',
    })) as string
    checks.iaIntegrated = currentIA.toLowerCase() === iaAddress.toLowerCase()
    env.showMessage(`  IA integrated: ${checks.iaIntegrated ? '✓' : '✗'} (current: ${currentIA})`)

    // Check GraphToken.isMinter(IA)
    checks.iaMinter = (await client.readContract({
      address: gtAddress as `0x${string}`,
      abi: GRAPH_TOKEN_ABI,
      functionName: 'isMinter',
      args: [iaAddress as `0x${string}`],
    })) as boolean
    env.showMessage(`  IA minter: ${checks.iaMinter ? '✓' : '✗'}`)

    // Check RM allocation on IA
    let rmAllocationOk = false
    try {
      const rmAllocation = (await client.readContract({
        address: iaAddress as `0x${string}`,
        abi: ISSUANCE_ALLOCATOR_ABI,
        functionName: 'getTargetAllocation',
        args: [rmAddress as `0x${string}`],
      })) as { totalAllocationRate: bigint; allocatorMintingRate: bigint; selfMintingRate: bigint }
      const iaRate = (await client.readContract({
        address: iaAddress as `0x${string}`,
        abi: ISSUANCE_ALLOCATOR_ABI,
        functionName: 'getIssuancePerBlock',
      })) as bigint
      rmAllocationOk =
        rmAllocation.allocatorMintingRate === 0n && rmAllocation.selfMintingRate === iaRate && iaRate > 0n
      env.showMessage(
        `  RM allocation: ${rmAllocationOk ? '✓' : '✗'} (self: ${formatGRT(rmAllocation.selfMintingRate)}, allocator: ${formatGRT(rmAllocation.allocatorMintingRate)})`,
      )
    } catch {
      env.showMessage(`  RM allocation: ✗ (not set)`)
    }

    // All checks passed?
    if (checks.iaIntegrated && checks.iaMinter && rmAllocationOk) {
      env.showMessage(`\n✅ RM already connected to IssuanceAllocator\n`)
      return
    }

    // Migration invariant: IA rate must match RM rate before connection
    if (!checks.iaIntegrated) {
      const rmRate = (await client.readContract({
        address: rmAddress as `0x${string}`,
        abi: REWARDS_MANAGER_DEPRECATED_ABI,
        functionName: 'issuancePerBlock',
      })) as bigint

      const iaRate = (await client.readContract({
        address: iaAddress as `0x${string}`,
        abi: ISSUANCE_ALLOCATOR_ABI,
        functionName: 'getIssuancePerBlock',
      })) as bigint

      if (iaRate !== rmRate) {
        env.showMessage(
          `\n❌ Migration invariant failed: IA.issuancePerBlock (${formatGRT(iaRate)}) != RM.issuancePerBlock (${formatGRT(rmRate)})`,
        )
        env.showMessage(`   IA must have the same overall rate as RM before connection.\n`)
        process.exit(1)
      }

      env.showMessage(`  Migration invariant: ✓ IA rate == RM rate (${formatGRT(iaRate)})`)
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
    if (!rmAllocationOk) {
      const iaRate = (await client.readContract({
        address: iaAddress as `0x${string}`,
        abi: ISSUANCE_ALLOCATOR_ABI,
        functionName: 'getIssuancePerBlock',
      })) as bigint
      const data = encodeFunctionData({
        abi: SET_TARGET_ALLOCATION_ABI,
        functionName: 'setTargetAllocation',
        args: [rmAddress as `0x${string}`, 0n, iaRate],
      })
      builder.addTx({ to: iaAddress, value: '0', data })
      env.showMessage(`  + IA.setTargetAllocation(RM, 0, ${formatGRT(iaRate)})`)
    }

    // 2. RM.setIssuanceAllocator(IA) — RM accepts IA as its allocator
    if (!checks.iaIntegrated) {
      const data = encodeFunctionData({
        abi: ISSUANCE_TARGET_ABI,
        functionName: 'setIssuanceAllocator',
        args: [iaAddress as `0x${string}`],
      })
      builder.addTx({ to: rmAddress, value: '0', data })
      env.showMessage(`  + RewardsManager.setIssuanceAllocator(${iaAddress})`)
    }

    // 3. GraphToken.addMinter(IA) — IA needs minter role for allocator-minting
    if (!checks.iaMinter) {
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

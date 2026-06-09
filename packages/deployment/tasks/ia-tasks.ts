import { task } from 'hardhat/config'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, custom, type PublicClient } from 'viem'

import { ISSUANCE_ALLOCATOR_ABI } from '../lib/abis.js'
import { formatGRT } from '../lib/format.js'
import { graph } from '../rocketh/deploy.js'

// -- Types --

interface Allocation {
  totalAllocationRate: bigint
  allocatorMintingRate: bigint
  selfMintingRate: bigint
}

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

// -- Helpers --

/**
 * Build a lowercased-address → human label map for the IA's known targets.
 * Targets the IA reports back that aren't in this map are shown by raw
 * address with an "(unknown)" marker.
 */
function buildTargetLabels(targetChainId: number): Map<string, string> {
  const labels = new Map<string, string>()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const add = (book: any, name: string, label: string): void => {
    if (book.entryExists(name)) {
      const addr = book.getEntry(name)?.address
      if (addr) labels.set(addr.toLowerCase(), label)
    }
  }
  const horizonBook = graph.getHorizonAddressBook(targetChainId)
  const issuanceBook = graph.getIssuanceAddressBook(targetChainId)
  add(horizonBook, 'RewardsManager', 'RM  (RewardsManager)')
  add(issuanceBook, 'RecurringAgreementManager', 'RAM (RecurringAgreementManager)')
  add(issuanceBook, 'DefaultAllocation', 'DA  (DefaultAllocation)')
  add(issuanceBook, 'ReclaimedRewards', 'ReclaimedRewards')
  return labels
}

/** Format `part` as a percentage of `whole` with two decimals. */
function formatPct(part: bigint, whole: bigint): string {
  if (whole === 0n) return 'n/a'
  // Two-decimal fixed-point: basis points then split.
  const bps = (part * 10000n) / whole
  const intPart = bps / 100n
  const fracPart = bps % 100n
  return `${intPart}.${fracPart.toString().padStart(2, '0')}%`
}

// -- Status action --

const statusAction: NewTaskActionFunction = async (_taskArgs, hre) => {
  // Connect to network
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  // Create viem client
  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  const issuanceBook = graph.getIssuanceAddressBook(targetChainId)
  const iaAddress = issuanceBook.entryExists('IssuanceAllocator')
    ? issuanceBook.getEntry('IssuanceAllocator')?.address
    : null

  if (!iaAddress) {
    console.error(`\nError: IssuanceAllocator not found in address book for chain ${targetChainId}`)
    return
  }

  const read = <T>(functionName: string, args: unknown[] = []): Promise<T> =>
    client.readContract({
      address: iaAddress as `0x${string}`,
      abi: ISSUANCE_ALLOCATOR_ABI,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      functionName: functionName as any,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      args: args as any,
    }) as Promise<T>

  console.log(`\n📊 IssuanceAllocator Status`)
  console.log(`   Address: ${iaAddress}`)
  console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)

  // Distinguish "no code at address" (fork predates deployment, fresh
  // non-forked node, or wrong network) from a genuine read failure — both
  // otherwise surface as an opaque revert.
  const code = await client.getCode({ address: iaAddress as `0x${string}` })
  if (!code || code === '0x') {
    console.error(`\n   ⚠️  No contract code at ${iaAddress} on ${networkName}.`)
    console.error(`      The address book points here for chain ${targetChainId}, but the chain has no`)
    console.error(`      bytecode there — a fork taken before the IA was deployed, a fresh (non-forked)`)
    console.error(`      node, or the wrong --network.\n`)
    return
  }

  // Top-level issuance / allocation totals
  let issuancePerBlock: bigint
  let totalAllocation: Allocation
  let targets: `0x${string}`[]
  try {
    ;[issuancePerBlock, totalAllocation, targets] = await Promise.all([
      read<bigint>('getIssuancePerBlock'),
      read<Allocation>('getTotalAllocation'),
      read<`0x${string}`[]>('getTargets'),
    ])
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    // A fork node lazily fetches state from its upstream RPC; if that RPC isn't
    // an archive node (or the forked block has been pruned) the fetch fails with
    // a "missing trie node" / "state is not available" error. Code is present
    // (getCode passed above), so this is an upstream-state problem, not a missing
    // or stale deployment.
    if (/missing trie node|state .* is not available|missing trie/i.test(msg)) {
      console.error(`\n   ⚠️  Contract code is present, but the fork's upstream RPC could not serve its state.`)
      console.error(`      The node you forked from is not an archive node, or the fork block has been pruned.`)
      console.error(`      Re-fork at a recent block against an archive RPC (set ARBITRUM_SEPOLIA_RPC to one).`)
      console.error(`      Underlying error: ${msg}\n`)
    } else {
      console.error(`\n   ⚠️  Contract code is present but reading allocator state failed.`)
      console.error(`      The deployed implementation may predate the GIP-0088 IssuanceAllocator interface.`)
      console.error(`      Underlying error: ${msg}\n`)
    }
    return
  }

  console.log(`\n💰 Issuance`)
  if (issuancePerBlock === 0n) {
    console.log(`   Issuance per block: 0 (not configured — issuance-connect not run)`)
  } else {
    console.log(`   Issuance per block: ${formatGRT(issuancePerBlock)}`)
  }
  console.log(
    `   Total allocated:    ${formatGRT(totalAllocation.totalAllocationRate)} (${formatPct(totalAllocation.totalAllocationRate, issuancePerBlock)})`,
  )
  console.log(`     allocator-minted: ${formatGRT(totalAllocation.allocatorMintingRate)}`)
  console.log(`     self-minted:      ${formatGRT(totalAllocation.selfMintingRate)}`)
  if (issuancePerBlock > 0n) {
    if (totalAllocation.totalAllocationRate === issuancePerBlock) {
      console.log(`   ✓ Fully allocated (100% of issuance)`)
    } else if (totalAllocation.totalAllocationRate < issuancePerBlock) {
      const unallocated = issuancePerBlock - totalAllocation.totalAllocationRate
      console.log(`   ⚠️  Under-allocated by ${formatGRT(unallocated)} — this issuance is not minted`)
    } else {
      console.log(`   ⚠️  Over-allocated — total exceeds issuance per block`)
    }
  }

  // Per-target breakdown
  const labels = buildTargetLabels(targetChainId)
  const ramAddress = issuanceBook.entryExists('RecurringAgreementManager')
    ? (issuanceBook.getEntry('RecurringAgreementManager')?.address ?? null)
    : null

  console.log(`\n🎯 Targets (${targets.length})`)
  if (targets.length === 0) {
    console.log(`   (none — no targets configured)`)
  }

  let ramSeen = false
  for (const target of targets) {
    const alloc = await read<Allocation>('getTargetAllocation', [target])
    const known = labels.get(target.toLowerCase())
    const label = known ?? `${target} (unknown)`
    if (ramAddress && target.toLowerCase() === ramAddress.toLowerCase()) ramSeen = true
    console.log(`\n   ${label}`)
    if (known) console.log(`     ${target}`)
    console.log(
      `     total:     ${formatGRT(alloc.totalAllocationRate)} (${formatPct(alloc.totalAllocationRate, issuancePerBlock)})`,
    )
    console.log(`     allocator: ${formatGRT(alloc.allocatorMintingRate)}`)
    console.log(`     self:      ${formatGRT(alloc.selfMintingRate)}`)
  }

  // RAM call-out — only for the cases the targets breakdown above can't show.
  // When RAM has an allocation it already appears in that list (labelled), so
  // re-printing it would just duplicate. This flags the problem cases instead.
  if (!ramSeen) {
    console.log(`\n🔁 RAM (RecurringAgreementManager)`)
    if (!ramAddress) {
      console.log(`   ✗ Not in address book for chain ${targetChainId} (not deployed)`)
    } else if (ramAddress === ZERO_ADDRESS) {
      console.log(`   ✗ Address book entry is the zero address`)
    } else {
      console.log(`   ✗ Deployed (${ramAddress}) but has NO allocation on the IA`)
      console.log(`     issuance-allocate (S10/S11) has not run, or rates are 0 in config/<network>.json5`)
    }
  }

  console.log()
}

// -- Task definition --

/**
 * Show IssuanceAllocator status: issuance per block, total allocation, and a
 * per-target breakdown (RM, RAM, DefaultAllocation, …) with each target's
 * allocator/self minting rates and share of issuance.
 *
 * Calls out the RAM (RecurringAgreementManager) allocation explicitly —
 * `deploy:status` only reports aggregate "100% allocated", which can hide a
 * missing RAM allocation when RM self-minting covers the slack.
 *
 * Read-only; no transaction, no key required.
 *
 * Examples:
 *   npx hardhat ia:status --network arbitrumSepolia
 */
export const iaStatusTask = task('ia:status', 'Show IssuanceAllocator allocations (incl. RAM)')
  .setAction(async () => ({ default: statusAction }))
  .build()

export default [iaStatusTask]

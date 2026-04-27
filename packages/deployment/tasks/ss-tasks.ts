import { task } from 'hardhat/config'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, custom, type PublicClient } from 'viem'

// Minimal ABI for RewardsManager public storage variable (not in the IRewardsManager interface)
const REWARDS_MANAGER_SIGNAL_ABI = [
  {
    inputs: [],
    name: 'minimumSubgraphSignal',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const
import { formatGRT } from '../lib/format.js'
import { formatDuration } from '../lib/task-utils.js'
import { graph } from '../rocketh/deploy.js'

// -- ABIs --

// Minimal ABI for SubgraphService view functions
const SUBGRAPH_SERVICE_ABI = [
  {
    inputs: [],
    name: 'getProvisionTokensRange',
    outputs: [{ type: 'uint256' }, { type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getDelegationRatio',
    outputs: [{ type: 'uint32' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'stakeToFeesRatio',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'curationFeesCut',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'maxPOIStaleness',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getThawingPeriodRange',
    outputs: [{ type: 'uint64' }, { type: 'uint64' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getVerifierCutRange',
    outputs: [{ type: 'uint32' }, { type: 'uint32' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getDisputeManager',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getGraphTallyCollector',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getCuration',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getBlockClosingAllocationWithActiveAgreement',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const

// -- Helpers --

const PPM = 1_000_000

function formatPPM(value: bigint | number): string {
  const pct = (Number(value) / PPM) * 100
  return `${pct}% (${value} PPM)`
}

// -- Task Action --

const statusAction: NewTaskActionFunction = async (_taskArgs, hre) => {
  // Connect to network
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  // Get SubgraphService address
  const ssBook = graph.getSubgraphServiceAddressBook(targetChainId)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const ssAddress = (ssBook as any).entryExists('SubgraphService')
    ? // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (ssBook as any).getEntry('SubgraphService')?.address
    : null

  if (!ssAddress) {
    console.error(`\nError: SubgraphService not found in address book for chain ${targetChainId}`)
    return
  }

  // Get RewardsManager address
  const horizonBook = graph.getHorizonAddressBook(targetChainId)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rmAddress = (horizonBook as any).entryExists('RewardsManager')
    ? // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (horizonBook as any).getEntry('RewardsManager')?.address
    : null

  console.log(`\n📊 SubgraphService Status`)
  console.log(`   Address: ${ssAddress}`)
  console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)

  // Batch-read all SubgraphService parameters
  const [
    provisionRange,
    delegationRatio,
    stakeToFees,
    curationCut,
    poiStaleness,
    thawingRange,
    verifierCutRange,
    disputeManager,
    tallyCollector,
    curation,
  ] = await Promise.all([
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'getProvisionTokensRange',
    }) as Promise<[bigint, bigint]>,
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'getDelegationRatio',
    }) as Promise<number>,
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'stakeToFeesRatio',
    }) as Promise<bigint>,
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'curationFeesCut',
    }) as Promise<bigint>,
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'maxPOIStaleness',
    }) as Promise<bigint>,
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'getThawingPeriodRange',
    }) as Promise<readonly [bigint, bigint]>,
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'getVerifierCutRange',
    }) as Promise<readonly [number, number]>,
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'getDisputeManager',
    }) as Promise<string>,
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'getGraphTallyCollector',
    }) as Promise<string>,
    client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'getCuration',
    }) as Promise<string>,
  ])

  // Try newer functions that may not be on current deployment
  let blockClosingWithAgreement: boolean | null = null
  try {
    blockClosingWithAgreement = (await client.readContract({
      address: ssAddress as `0x${string}`,
      abi: SUBGRAPH_SERVICE_ABI,
      functionName: 'getBlockClosingAllocationWithActiveAgreement',
    })) as boolean
  } catch {
    // Not available on current implementation
  }

  // Display SubgraphService parameters
  console.log(`\n🔧 Provision Parameters`)
  console.log(`   Min provision tokens: ${formatGRT(provisionRange[0])}`)
  if (provisionRange[1] < 2n ** 256n - 1n) {
    console.log(`   Max provision tokens: ${formatGRT(provisionRange[1])}`)
  } else {
    console.log(`   Max provision tokens: unlimited`)
  }
  console.log(`   Delegation ratio: ${delegationRatio}x`)

  console.log(`\n📐 Thawing & Verifier Ranges`)
  if (thawingRange[0] === thawingRange[1]) {
    console.log(`   Thawing period: ${formatDuration(thawingRange[0])} (fixed)`)
  } else {
    console.log(`   Thawing period: ${formatDuration(thawingRange[0])} – ${formatDuration(thawingRange[1])}`)
  }
  console.log(`   Verifier cut: ${formatPPM(verifierCutRange[0])} – ${formatPPM(verifierCutRange[1])}`)

  console.log(`\n💰 Fee Parameters`)
  console.log(`   Stake to fees ratio: ${stakeToFees}`)
  console.log(`   Curation fees cut: ${formatPPM(curationCut)}`)

  console.log(`\n⏱️  Staleness`)
  console.log(`   Max POI staleness: ${formatDuration(poiStaleness)} (${poiStaleness} seconds)`)

  if (blockClosingWithAgreement !== null) {
    console.log(`\n🔒 Agreement Guards`)
    console.log(`   Block closing allocation with active agreement: ${blockClosingWithAgreement ? 'yes' : 'no'}`)
  }

  console.log(`\n🔗 Linked Contracts`)
  console.log(`   DisputeManager: ${disputeManager}`)
  console.log(`   GraphTallyCollector: ${tallyCollector}`)
  console.log(`   Curation: ${curation}`)

  // RewardsManager parameters
  if (rmAddress) {
    console.log(`\n📊 RewardsManager`)
    console.log(`   Address: ${rmAddress}`)

    try {
      const minimumSignal = (await client.readContract({
        address: rmAddress as `0x${string}`,
        abi: REWARDS_MANAGER_SIGNAL_ABI,
        functionName: 'minimumSubgraphSignal',
      })) as bigint

      if (minimumSignal === 0n) {
        console.log(`   Minimum subgraph signal: 0 (disabled)`)
      } else {
        console.log(`   Minimum subgraph signal: ${formatGRT(minimumSignal)}`)
      }
    } catch {
      console.log(`   Minimum subgraph signal: ? (not readable)`)
    }
  }

  console.log()
}

// -- Task Definition --

/**
 * Show SubgraphService configuration parameters
 *
 * Displays provision requirements, fee parameters, staleness thresholds,
 * and linked contract addresses.
 *
 * Examples:
 *   npx hardhat ss:status --network arbitrumOne
 *   npx hardhat ss:status --network arbitrumSepolia
 */
export const ssStatusTask = task('ss:status', 'Show SubgraphService configuration parameters')
  .setAction(async () => ({ default: statusAction }))
  .build()

export default [ssStatusTask]

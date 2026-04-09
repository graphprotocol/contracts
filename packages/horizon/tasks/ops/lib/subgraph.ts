/**
 * Subgraph query utilities for TAP Escrow Recovery & Legacy Allocation Closure operations
 */

import type { Allocation, EscrowAccount } from './types'

// ============================================
// Subgraph Endpoints
// ============================================

const SUBGRAPH_ENDPOINTS = {
  // Graph Network subgraph for legacy allocations
  GRAPH_NETWORK: 'https://gateway.thegraph.com/api/{apiKey}/subgraphs/id/DZz4kDTdmzWLWsV373w2bSmoar3umKKH9y82SUKr5qmp',
  // TAP subgraph for escrow accounts
  TAP: 'https://gateway.thegraph.com/api/{apiKey}/subgraphs/id/4sukbNVTzGELnhdnpyPqsf1QqtzNHEYKKmJkgaT8z6M1',
} as const

// ============================================
// GraphQL Queries
// ============================================

const LEGACY_ALLOCATIONS_QUERY = `
  query LegacyAllocations($first: Int!, $skip: Int!, $excludedIndexers: [String!]) {
    allocations(
      first: $first
      skip: $skip
      where: {
        status: Active
        isLegacy: true
        allocatedTokens_gt: 0
        indexer_not_in: $excludedIndexers
      }
      orderBy: allocatedTokens
      orderDirection: desc
    ) {
      id
      allocatedTokens
      createdAtEpoch
      closedAtEpoch
      createdAtBlockNumber
      status
      poi
      indexer {
        id
        allocatedTokens
        stakedTokens
        url
      }
      subgraphDeployment {
        id
        ipfsHash
      }
    }
  }
`

const ESCROW_ACCOUNTS_QUERY = `
  query EscrowAccounts($first: Int!, $skip: Int!, $senders: [String!]) {
    escrowAccounts(
      first: $first
      skip: $skip
      where: {
        sender_in: $senders
        balance_gt: 0
      }
      orderBy: balance
      orderDirection: desc
    ) {
      id
      sender {
        id
      }
      receiver {
        id
      }
      balance
      thawEndTimestamp
      totalAmountThawing
    }
  }
`

// ============================================
// Query Functions
// ============================================

/**
 * Execute a GraphQL query against a subgraph
 */
async function executeQuery<T>(
  endpoint: string,
  query: string,
  variables: Record<string, unknown>,
): Promise<T> {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query, variables }),
  })

  if (!response.ok) {
    throw new Error(`Subgraph query failed: ${response.status} ${response.statusText}`)
  }

  const json = await response.json()

  if (json.errors) {
    throw new Error(`GraphQL errors: ${JSON.stringify(json.errors)}`)
  }

  return json.data
}

/**
 * Paginate through all results from a subgraph query
 */
async function paginateQuery<T>(
  endpoint: string,
  query: string,
  variables: Record<string, unknown>,
  resultKey: string,
  pageSize: number = 1000,
): Promise<T[]> {
  const results: T[] = []
  let skip = 0
  let hasMore = true

  while (hasMore) {
    const data = await executeQuery<Record<string, T[]>>(endpoint, query, {
      ...variables,
      first: pageSize,
      skip,
    })

    const pageResults = data[resultKey] || []
    results.push(...pageResults)

    if (pageResults.length < pageSize) {
      hasMore = false
    } else {
      skip += pageSize
    }
  }

  return results
}

/**
 * Query legacy allocations from Graph Network subgraph
 */
export async function queryLegacyAllocations(
  apiKey: string,
  excludedIndexers: string[],
): Promise<Allocation[]> {
  const endpoint = SUBGRAPH_ENDPOINTS.GRAPH_NETWORK.replace('{apiKey}', apiKey)

  // Normalize addresses to lowercase for subgraph query
  const normalizedExcluded = excludedIndexers.map((addr) => addr.toLowerCase())

  interface RawAllocation {
    id: string
    allocatedTokens: string
    createdAtEpoch: number
    closedAtEpoch: number | null
    createdAtBlockNumber: number
    status: string
    poi: string | null
    indexer: {
      id: string
      allocatedTokens: string
      stakedTokens: string
      url: string | null
    }
    subgraphDeployment: {
      id: string
      ipfsHash: string
    }
  }

  const rawAllocations = await paginateQuery<RawAllocation>(
    endpoint,
    LEGACY_ALLOCATIONS_QUERY,
    { excludedIndexers: normalizedExcluded },
    'allocations',
  )

  // Transform raw data to typed allocations
  return rawAllocations.map((raw) => ({
    id: raw.id,
    allocatedTokens: BigInt(raw.allocatedTokens),
    createdAtEpoch: raw.createdAtEpoch,
    closedAtEpoch: raw.closedAtEpoch,
    createdAtBlockNumber: raw.createdAtBlockNumber,
    status: raw.status as Allocation['status'],
    poi: raw.poi,
    indexer: {
      id: raw.indexer.id,
      allocatedTokens: BigInt(raw.indexer.allocatedTokens),
      stakedTokens: BigInt(raw.indexer.stakedTokens),
      url: raw.indexer.url || null,
    },
    subgraphDeployment: raw.subgraphDeployment,
  }))
}

/**
 * Query TAP escrow accounts from TAP subgraph
 */
export async function queryEscrowAccounts(
  apiKey: string,
  senderAddresses: string[],
  excludedReceivers: string[] = [],
): Promise<EscrowAccount[]> {
  const endpoint = SUBGRAPH_ENDPOINTS.TAP.replace('{apiKey}', apiKey)

  // Normalize addresses to lowercase for subgraph query
  const normalizedSenders = senderAddresses.map((addr) => addr.toLowerCase())
  const normalizedExcludedReceivers = excludedReceivers.map((addr) => addr.toLowerCase())

  interface RawEscrowAccount {
    id: string
    sender: { id: string }
    receiver: { id: string }
    balance: string
    thawEndTimestamp: string
    totalAmountThawing: string
  }

  const rawAccounts = await paginateQuery<RawEscrowAccount>(
    endpoint,
    ESCROW_ACCOUNTS_QUERY,
    { senders: normalizedSenders },
    'escrowAccounts',
  )

  // Transform raw data to typed escrow accounts and filter out excluded receivers
  return rawAccounts
    .filter((raw) => !normalizedExcludedReceivers.includes(raw.receiver.id.toLowerCase()))
    .map((raw) => ({
      id: raw.id,
      sender: raw.sender.id,
      receiver: raw.receiver.id,
      balance: BigInt(raw.balance),
      amountThawing: BigInt(raw.totalAmountThawing),
      thawEndTimestamp: BigInt(raw.thawEndTimestamp),
      totalAmountThawing: BigInt(raw.totalAmountThawing),
    }))
}

/**
 * Group allocations by indexer for summary reporting
 */
export function groupAllocationsByIndexer(allocations: Allocation[]) {
  const indexerMap = new Map<string, Allocation[]>()

  for (const allocation of allocations) {
    const indexerId = allocation.indexer.id
    if (!indexerMap.has(indexerId)) {
      indexerMap.set(indexerId, [])
    }
    indexerMap.get(indexerId)!.push(allocation)
  }

  return Array.from(indexerMap.entries()).map(([indexer, allocs]) => ({
    indexer,
    indexerUrl: allocs[0]?.indexer.url || null,
    allocations: allocs,
    totalAllocatedTokens: allocs.reduce((sum, a) => sum + a.allocatedTokens, 0n),
    allocationCount: allocs.length,
  }))
}

/**
 * Group escrow accounts by sender for summary reporting
 */
export function groupEscrowAccountsBySender(accounts: EscrowAccount[]) {
  const senderMap = new Map<string, EscrowAccount[]>()

  for (const account of accounts) {
    const senderId = account.sender
    if (!senderMap.has(senderId)) {
      senderMap.set(senderId, [])
    }
    senderMap.get(senderId)!.push(account)
  }

  return Array.from(senderMap.entries()).map(([sender, accts]) => ({
    sender,
    accounts: accts,
    totalBalance: accts.reduce((sum, a) => sum + a.balance, 0n),
    totalAmountThawing: accts.reduce((sum, a) => sum + a.amountThawing, 0n),
    accountCount: accts.length,
  }))
}

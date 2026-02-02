/**
 * Type definitions for TAP Escrow Recovery & Legacy Allocation Closure operations
 */

// ============================================
// Legacy Allocation Types
// ============================================

/**
 * Allocation data from Graph Network subgraph
 */
export interface Allocation {
  id: string
  allocatedTokens: bigint
  createdAtEpoch: number
  closedAtEpoch: number | null
  createdAtBlockNumber: number
  status: AllocationStatus
  poi: string | null
  indexer: Indexer
  subgraphDeployment: SubgraphDeployment
}

export interface Indexer {
  id: string
  allocatedTokens: bigint
  stakedTokens: bigint
  url: string | null
}

export interface SubgraphDeployment {
  id: string
  ipfsHash: string
}

export type AllocationStatus = 'Active' | 'Closed' | 'Finalized' | 'Claimed'

/**
 * Aggregated allocation data by indexer
 */
export interface IndexerAllocationSummary {
  indexer: string
  indexerUrl: string | null
  allocations: Allocation[]
  totalAllocatedTokens: bigint
  allocationCount: number
}

// ============================================
// TAP Escrow Types
// ============================================

/**
 * Escrow account data from TAP subgraph
 */
export interface EscrowAccount {
  id: string
  sender: string
  receiver: string
  balance: bigint
  amountThawing: bigint
  thawEndTimestamp: bigint
  totalAmountThawing: bigint
}

/**
 * Sender summary with all their escrow accounts
 */
export interface SenderEscrowSummary {
  sender: string
  accounts: EscrowAccount[]
  totalBalance: bigint
  totalAmountThawing: bigint
  accountCount: number
}

// ============================================
// Transaction Types
// ============================================

/**
 * Transaction result for tracking execution
 */
export interface TransactionResult {
  success: boolean
  txHash?: string
  error?: string
  gasUsed?: bigint
}

/**
 * Result of closing an allocation
 */
export interface CloseAllocationResult extends TransactionResult {
  allocationId: string
  indexer: string
}

/**
 * Result of thawing escrow funds
 */
export interface ThawResult extends TransactionResult {
  sender: string
  receiver: string
  amount: bigint
  thawEndTimestamp?: bigint
}

/**
 * Result of withdrawing escrow funds
 */
export interface WithdrawResult extends TransactionResult {
  sender: string
  receiver: string
  amount: bigint
}

// ============================================
// Calldata Types
// ============================================

/**
 * Calldata for external execution (Fireblocks, Safe, etc.)
 */
export interface CalldataEntry {
  to: string
  data: string
  value: string
  description: string
}

/**
 * Batch of calldata entries
 */
export interface CalldataBatch {
  timestamp: string
  network: string
  chainId: number
  entries: CalldataEntry[]
}

// ============================================
// Report Types
// ============================================

/**
 * Report metadata
 */
export interface ReportMetadata {
  timestamp: string
  network: string
  chainId: number
  generatedBy: string
}

/**
 * Legacy allocations report
 */
export interface AllocationsReport extends ReportMetadata {
  excludedIndexers: string[]
  totalAllocations: number
  totalAllocatedTokens: bigint
  allocations: Allocation[]
  summaryByIndexer: IndexerAllocationSummary[]
}

/**
 * TAP escrow report
 */
export interface EscrowReport extends ReportMetadata {
  senderAddresses: string[]
  excludedReceivers: string[]
  totalAccounts: number
  totalBalance: bigint
  totalAmountThawing: bigint
  accounts: EscrowAccount[]
  summaryBySender: SenderEscrowSummary[]
}

/**
 * Execution results report
 */
export interface ExecutionReport<T extends TransactionResult> extends ReportMetadata {
  mode: 'execute' | 'calldata-only' | 'dry-run'
  totalTransactions: number
  successCount: number
  failureCount: number
  results: T[]
}

// ============================================
// Constants
// ============================================

/**
 * Default configuration values
 */
export const DEFAULTS = {
  // Upgrade indexer - excluded by default from allocation closing
  UPGRADE_INDEXER: '0xbdfb5ee5a2abf4fc7bb1bd1221067aef7f9de491',

  // Gateway sender addresses for TAP escrow queries
  SENDER_ADDRESSES: [
    '0xdde4cffd3d9052a9cb618fc05a1cd02be1f2f467', // Primary (~1,092,951 GRT)
    '0xdd6a6f76eb36b873c1c184e8b9b9e762fe216490', // Secondary (~2,843 GRT)
  ],

  // Contract addresses (Arbitrum One)
  HORIZON_STAKING: '0x00669A4CF01450B64E8A2A20E9b1FCB71E61eF03',
  TAP_ESCROW: '0x8f477709eF277d4A880801D01A140a9CF88bA0d3',

  // Output directory
  OUTPUT_DIR: './ops-output',
} as const

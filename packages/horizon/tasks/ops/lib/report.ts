/**
 * Report generation utilities for TAP Escrow Recovery & Legacy Allocation Closure operations
 */

import * as fs from 'fs'
import * as path from 'path'

import type {
  Allocation,
  AllocationsReport,
  CalldataBatch,
  CloseAllocationResult,
  EscrowAccount,
  EscrowReport,
  ExecutionReport,
  IndexerAllocationSummary,
  SenderEscrowSummary,
  ThawResult,
  TransactionResult,
  WithdrawResult,
} from './types'
import { DEFAULTS } from './types'

// ============================================
// Directory Setup
// ============================================

/**
 * Ensure output directory exists
 */
export function ensureOutputDir(outputDir: string = DEFAULTS.OUTPUT_DIR): void {
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true })
  }

  const calldataDir = path.join(outputDir, 'calldata')
  if (!fs.existsSync(calldataDir)) {
    fs.mkdirSync(calldataDir, { recursive: true })
  }
}

/**
 * Generate timestamp string for filenames
 */
function getTimestamp(): string {
  const now = new Date()
  return now.toISOString().replace(/[:.]/g, '-').slice(0, 19)
}

// ============================================
// GRT Formatting
// ============================================

/**
 * Format GRT amount for display (18 decimals)
 */
export function formatGRT(amount: bigint): string {
  const decimals = 18n
  const divisor = 10n ** decimals
  const whole = amount / divisor
  const fraction = amount % divisor
  const fractionStr = fraction.toString().padStart(Number(decimals), '0').slice(0, 4)
  return `${whole.toLocaleString()}.${fractionStr}`
}

/**
 * Format GRT as simple number string for CSV
 */
export function formatGRTSimple(amount: bigint): string {
  const decimals = 18n
  const divisor = 10n ** decimals
  const whole = amount / divisor
  const fraction = amount % divisor
  const fractionStr = fraction.toString().padStart(Number(decimals), '0').slice(0, 6)
  return `${whole}.${fractionStr}`
}

// ============================================
// Allocations Report
// ============================================

/**
 * Generate allocations report
 */
export function generateAllocationsReport(
  allocations: Allocation[],
  summaryByIndexer: IndexerAllocationSummary[],
  excludedIndexers: string[],
  network: string,
  chainId: number,
): AllocationsReport {
  return {
    timestamp: new Date().toISOString(),
    network,
    chainId,
    generatedBy: 'ops:allocations:query',
    excludedIndexers,
    totalAllocations: allocations.length,
    totalAllocatedTokens: allocations.reduce((sum, a) => sum + a.allocatedTokens, 0n),
    allocations,
    summaryByIndexer,
  }
}

/**
 * Write allocations report to files
 */
export function writeAllocationsReport(
  report: AllocationsReport,
  outputDir: string = DEFAULTS.OUTPUT_DIR,
): { jsonPath: string; csvPath: string } {
  ensureOutputDir(outputDir)
  const timestamp = getTimestamp()

  // Write JSON report
  const jsonPath = path.join(outputDir, `allocations-${timestamp}.json`)
  fs.writeFileSync(
    jsonPath,
    JSON.stringify(
      report,
      (_, value) => (typeof value === 'bigint' ? value.toString() : value),
      2,
    ),
  )

  // Write CSV report
  const csvPath = path.join(outputDir, `allocations-${timestamp}.csv`)
  const csvHeader = 'allocation_id,indexer,indexer_url,allocated_tokens_grt,subgraph_deployment,created_epoch,status\n'
  const csvRows = report.allocations.map((a) =>
    `${a.id},${a.indexer.id},${a.indexer.url || 'N/A'},${formatGRTSimple(a.allocatedTokens)},${a.subgraphDeployment.ipfsHash},${a.createdAtEpoch},${a.status}`,
  ).join('\n')
  fs.writeFileSync(csvPath, csvHeader + csvRows)

  return { jsonPath, csvPath }
}

/**
 * Print allocations summary to console
 */
export function printAllocationsSummary(report: AllocationsReport): void {
  console.log('\n========== Legacy Allocations Summary ==========')
  console.log(`Network: ${report.network} (Chain ID: ${report.chainId})`)
  console.log(`Timestamp: ${report.timestamp}`)
  console.log(`Excluded Indexers: ${report.excludedIndexers.join(', ') || 'None'}`)
  console.log('')
  console.log(`Total Allocations: ${report.totalAllocations}`)
  console.log(`Total Allocated GRT: ${formatGRT(report.totalAllocatedTokens)}`)
  console.log('')

  console.log('By Indexer:')
  console.log('─'.repeat(110))
  console.log('| Indexer                                    | URL                          | Allocations | Allocated GRT      |')
  console.log('─'.repeat(110))
  for (const summary of report.summaryByIndexer.slice(0, 15)) {
    const urlDisplay = summary.indexerUrl ? summary.indexerUrl.slice(0, 28) : 'N/A'
    console.log(
      `| ${summary.indexer.slice(0, 42).padEnd(42)} | ${urlDisplay.padEnd(28)} | ${summary.allocationCount.toString().padStart(11)} | ${formatGRT(summary.totalAllocatedTokens).padStart(18)} |`,
    )
  }
  if (report.summaryByIndexer.length > 15) {
    console.log(`| ... and ${report.summaryByIndexer.length - 15} more indexers`.padEnd(109) + '|')
  }
  console.log('─'.repeat(110))
}

// ============================================
// Escrow Report
// ============================================

/**
 * Generate escrow report
 */
export function generateEscrowReport(
  accounts: EscrowAccount[],
  summaryBySender: SenderEscrowSummary[],
  senderAddresses: string[],
  excludedReceivers: string[],
  network: string,
  chainId: number,
): EscrowReport {
  return {
    timestamp: new Date().toISOString(),
    network,
    chainId,
    generatedBy: 'ops:escrow:query',
    senderAddresses,
    excludedReceivers,
    totalAccounts: accounts.length,
    totalBalance: accounts.reduce((sum, a) => sum + a.balance, 0n),
    totalAmountThawing: accounts.reduce((sum, a) => sum + a.amountThawing, 0n),
    accounts,
    summaryBySender,
  }
}

/**
 * Write escrow report to files
 */
export function writeEscrowReport(
  report: EscrowReport,
  outputDir: string = DEFAULTS.OUTPUT_DIR,
): { jsonPath: string; csvPath: string } {
  ensureOutputDir(outputDir)
  const timestamp = getTimestamp()

  // Write JSON report
  const jsonPath = path.join(outputDir, `escrow-accounts-${timestamp}.json`)
  fs.writeFileSync(
    jsonPath,
    JSON.stringify(
      report,
      (_, value) => (typeof value === 'bigint' ? value.toString() : value),
      2,
    ),
  )

  // Write CSV report
  const csvPath = path.join(outputDir, `escrow-accounts-${timestamp}.csv`)
  const csvHeader = 'account_id,sender,receiver,balance_grt,amount_thawing_grt,thaw_end_timestamp,recoverable_grt\n'
  const csvRows = report.accounts.map((a) => {
    const recoverable = a.balance - a.amountThawing
    return `${a.id},${a.sender},${a.receiver},${formatGRTSimple(a.balance)},${formatGRTSimple(a.amountThawing)},${a.thawEndTimestamp},${formatGRTSimple(recoverable > 0n ? recoverable : 0n)}`
  }).join('\n')
  fs.writeFileSync(csvPath, csvHeader + csvRows)

  return { jsonPath, csvPath }
}

/**
 * Print escrow summary to console
 */
export function printEscrowSummary(report: EscrowReport): void {
  console.log('\n========== TAP Escrow Accounts Summary ==========')
  console.log(`Network: ${report.network} (Chain ID: ${report.chainId})`)
  console.log(`Timestamp: ${report.timestamp}`)
  console.log(`Sender Addresses: ${report.senderAddresses.join(', ')}`)
  console.log(`Excluded Receivers: ${report.excludedReceivers.join(', ') || 'None'}`)
  console.log('')
  console.log(`Total Accounts: ${report.totalAccounts}`)
  console.log(`Total Balance: ${formatGRT(report.totalBalance)} GRT`)
  console.log(`Total Amount Thawing: ${formatGRT(report.totalAmountThawing)} GRT`)
  console.log(`Recoverable (balance - thawing): ${formatGRT(report.totalBalance - report.totalAmountThawing)} GRT`)
  console.log('')

  console.log('By Sender:')
  console.log('─'.repeat(90))
  console.log('| Sender                                     | Accounts | Balance GRT        | Thawing GRT        |')
  console.log('─'.repeat(90))
  for (const summary of report.summaryBySender) {
    console.log(
      `| ${summary.sender.slice(0, 42).padEnd(42)} | ${summary.accountCount.toString().padStart(8)} | ${formatGRT(summary.totalBalance).padStart(18)} | ${formatGRT(summary.totalAmountThawing).padStart(18)} |`,
    )
  }
  console.log('─'.repeat(90))
}

// ============================================
// Execution Reports
// ============================================

/**
 * Generate execution report
 */
export function generateExecutionReport<T extends TransactionResult>(
  results: T[],
  mode: 'execute' | 'calldata-only' | 'dry-run',
  network: string,
  chainId: number,
  generatedBy: string,
): ExecutionReport<T> {
  return {
    timestamp: new Date().toISOString(),
    network,
    chainId,
    generatedBy,
    mode,
    totalTransactions: results.length,
    successCount: results.filter((r) => r.success).length,
    failureCount: results.filter((r) => !r.success).length,
    results,
  }
}

/**
 * Write execution report to file
 */
export function writeExecutionReport<T extends TransactionResult>(
  report: ExecutionReport<T>,
  prefix: string,
  outputDir: string = DEFAULTS.OUTPUT_DIR,
): string {
  ensureOutputDir(outputDir)
  const timestamp = getTimestamp()
  const filePath = path.join(outputDir, `${prefix}-results-${timestamp}.json`)

  fs.writeFileSync(
    filePath,
    JSON.stringify(
      report,
      (_, value) => (typeof value === 'bigint' ? value.toString() : value),
      2,
    ),
  )

  return filePath
}

/**
 * Print execution summary to console
 */
export function printExecutionSummary<T extends TransactionResult>(
  report: ExecutionReport<T>,
  operationType: string,
): void {
  console.log(`\n========== ${operationType} Execution Summary ==========`)
  console.log(`Mode: ${report.mode}`)
  console.log(`Network: ${report.network} (Chain ID: ${report.chainId})`)
  console.log('')
  console.log(`Total Transactions: ${report.totalTransactions}`)
  console.log(`Successful: ${report.successCount}`)
  console.log(`Failed: ${report.failureCount}`)

  if (report.failureCount > 0) {
    console.log('\nFailed Transactions:')
    for (const result of report.results.filter((r) => !r.success)) {
      console.log(`  - Error: ${result.error}`)
    }
  }
}

// ============================================
// Calldata Reports
// ============================================

/**
 * Write calldata batch to file
 */
export function writeCalldataBatch(
  batch: CalldataBatch,
  prefix: string,
  outputDir: string = DEFAULTS.OUTPUT_DIR,
): string {
  ensureOutputDir(outputDir)
  const timestamp = getTimestamp()
  const filePath = path.join(outputDir, 'calldata', `${prefix}-${timestamp}.json`)

  fs.writeFileSync(filePath, JSON.stringify(batch, null, 2))

  return filePath
}

/**
 * Print calldata summary to console
 */
export function printCalldataSummary(batch: CalldataBatch, prefix: string): void {
  console.log(`\n========== ${prefix} Calldata Summary ==========`)
  console.log(`Network: ${batch.network} (Chain ID: ${batch.chainId})`)
  console.log(`Timestamp: ${batch.timestamp}`)
  console.log(`Total Transactions: ${batch.entries.length}`)
  console.log('')

  console.log('First 5 entries:')
  for (const entry of batch.entries.slice(0, 5)) {
    console.log(`  - ${entry.description}`)
    console.log(`    To: ${entry.to}`)
    console.log(`    Data: ${entry.data.slice(0, 50)}...`)
  }

  if (batch.entries.length > 5) {
    console.log(`  ... and ${batch.entries.length - 5} more transactions`)
  }
}

// ============================================
// Load Reports (for use in subsequent tasks)
// ============================================

/**
 * Load allocations from a JSON file
 */
export function loadAllocationsFromFile(filePath: string): Allocation[] {
  const content = fs.readFileSync(filePath, 'utf-8')
  const report = JSON.parse(content) as AllocationsReport

  // Convert string values back to bigint
  return report.allocations.map((a) => ({
    ...a,
    allocatedTokens: BigInt(a.allocatedTokens as unknown as string),
    indexer: {
      ...a.indexer,
      allocatedTokens: BigInt(a.indexer.allocatedTokens as unknown as string),
      stakedTokens: BigInt(a.indexer.stakedTokens as unknown as string),
      url: a.indexer.url || null,
    },
  }))
}

/**
 * Load escrow accounts from a JSON file
 */
export function loadEscrowAccountsFromFile(filePath: string): EscrowAccount[] {
  const content = fs.readFileSync(filePath, 'utf-8')
  const report = JSON.parse(content) as EscrowReport

  // Convert string values back to bigint
  return report.accounts.map((a) => ({
    ...a,
    balance: BigInt(a.balance as unknown as string),
    amountThawing: BigInt(a.amountThawing as unknown as string),
    thawEndTimestamp: BigInt(a.thawEndTimestamp as unknown as string),
    totalAmountThawing: BigInt(a.totalAmountThawing as unknown as string),
  }))
}

/**
 * Legacy Allocations Operational Tasks
 *
 * Tasks for querying and force closing legacy allocations after Horizon migration.
 */

import { task, types, vars } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import { ZeroHash } from 'ethers'
import type { Signer } from 'ethers'

import { getImpersonatedSigner, isLocalNetwork } from './lib/fork-utils'
import {
  formatGRT,
  generateAllocationsReport,
  generateExecutionReport,
  loadAllocationsFromFile,
  printAllocationsSummary,
  printCalldataSummary,
  printExecutionSummary,
  writeAllocationsReport,
  writeCalldataBatch,
  writeExecutionReport,
} from './lib/report'
import { groupAllocationsByIndexer, queryLegacyAllocations } from './lib/subgraph'
import type { Allocation, CalldataBatch, CalldataEntry, CloseAllocationResult } from './lib/types'
import { DEFAULTS } from './lib/types'

// ============================================
// Query Legacy Allocations Task
// ============================================

task('ops:allocations:query', 'Query and report active legacy allocations from Graph Network subgraph')
  .addOptionalParam(
    'subgraphApiKey',
    'API key for The Graph Network gateway (can also use SUBGRAPH_API_KEY hardhat var)',
    undefined,
    types.string,
  )
  .addOptionalParam(
    'excludedIndexers',
    'Comma-separated list of indexer addresses to exclude',
    DEFAULTS.UPGRADE_INDEXER,
    types.string,
  )
  .addOptionalParam('outputDir', 'Output directory for reports', DEFAULTS.OUTPUT_DIR, types.string)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    console.log('\n========== Query Legacy Allocations ==========')

    // Get API key from args or hardhat vars
    let apiKey = args.subgraphApiKey
    if (!apiKey) {
      if (!vars.has('SUBGRAPH_API_KEY')) {
        throw new Error('No subgraph API key provided. Set --subgraph-api-key or use `npx hardhat vars set SUBGRAPH_API_KEY`')
      }
      apiKey = vars.get('SUBGRAPH_API_KEY')
    }

    // Parse excluded indexers
    const excludedIndexers = args.excludedIndexers
      .split(',')
      .map((addr: string) => addr.trim().toLowerCase())
      .filter((addr: string) => addr.length > 0)

    console.log(`Network: ${hre.network.name}`)
    console.log(`Chain ID: ${hre.network.config.chainId}`)
    console.log(`Excluded Indexers: ${excludedIndexers.join(', ')}`)
    console.log('')

    // Query subgraph
    console.log('Querying Graph Network subgraph for legacy allocations...')
    const allocations = await queryLegacyAllocations(apiKey, excludedIndexers)

    if (allocations.length === 0) {
      console.log('No active legacy allocations found.')
      return
    }

    // Group by indexer for summary
    const summaryByIndexer = groupAllocationsByIndexer(allocations)

    // Generate and write report
    const report = generateAllocationsReport(
      allocations,
      summaryByIndexer,
      excludedIndexers,
      hre.network.name,
      hre.network.config.chainId!,
    )

    const { jsonPath, csvPath } = writeAllocationsReport(report, args.outputDir)

    // Print summary
    printAllocationsSummary(report)

    console.log('\nReports written to:')
    console.log(`  JSON: ${jsonPath}`)
    console.log(`  CSV:  ${csvPath}`)
  })

// ============================================
// Close Legacy Allocations Task
// ============================================

task('ops:allocations:close', 'Force close legacy allocations')
  .addOptionalParam(
    'inputFile',
    'JSON file with allocations to close (from ops:allocations:query). If not provided, queries subgraph.',
    undefined,
    types.string,
  )
  .addOptionalParam(
    'subgraphApiKey',
    'API key for The Graph Network gateway (required if no inputFile)',
    undefined,
    types.string,
  )
  .addOptionalParam(
    'excludedIndexers',
    'Comma-separated list of indexer addresses to exclude',
    DEFAULTS.UPGRADE_INDEXER,
    types.string,
  )
  .addOptionalParam('limit', 'Maximum number of allocations to close (0 = all)', 0, types.int)
  .addOptionalParam('accountIndex', 'Derivation path index for the account', 0, types.int)
  .addOptionalParam('outputDir', 'Output directory for reports', DEFAULTS.OUTPUT_DIR, types.string)
  .addFlag('calldataOnly', 'Generate calldata without executing transactions')
  .addFlag('dryRun', 'Simulate without executing transactions')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    console.log('\n========== Close Legacy Allocations ==========')
    console.log(`Network: ${hre.network.name}`)
    console.log(`Chain ID: ${hre.network.config.chainId}`)
    console.log(`Mode: ${args.calldataOnly ? 'Calldata Only' : args.dryRun ? 'Dry Run' : 'Execute'}`)

    // Get allocations either from file or subgraph
    let allocations: Allocation[]

    if (args.inputFile) {
      console.log(`Loading allocations from: ${args.inputFile}`)
      allocations = loadAllocationsFromFile(args.inputFile)
    } else {
      // Query subgraph
      let apiKey = args.subgraphApiKey
      if (!apiKey) {
        if (!vars.has('SUBGRAPH_API_KEY')) {
          throw new Error('No subgraph API key provided. Set --subgraph-api-key or use `npx hardhat vars set SUBGRAPH_API_KEY`')
        }
        apiKey = vars.get('SUBGRAPH_API_KEY')
      }

      const excludedIndexers = args.excludedIndexers
        .split(',')
        .map((addr: string) => addr.trim().toLowerCase())
        .filter((addr: string) => addr.length > 0)

      console.log('Querying subgraph for legacy allocations...')
      allocations = await queryLegacyAllocations(apiKey, excludedIndexers)
    }

    if (allocations.length === 0) {
      console.log('No allocations to close.')
      return
    }

    // Apply limit if specified (sorted by allocatedTokens descending already)
    if (args.limit > 0 && allocations.length > args.limit) {
      console.log(`Limiting to first ${args.limit} allocations (of ${allocations.length} total)`)
      allocations = allocations.slice(0, args.limit)
    }

    console.log(`Found ${allocations.length} allocations to close`)
    console.log(`Total allocated GRT: ${formatGRT(allocations.reduce((sum, a) => sum + a.allocatedTokens, 0n))}`)

    // Initialize Graph Runtime Environment
    const graph = hre.graph()
    const horizonStaking = graph.horizon.contracts.HorizonStaking

    // Calldata-only mode
    if (args.calldataOnly) {
      const entries: CalldataEntry[] = allocations.map((allocation) => ({
        to: horizonStaking.target as string,
        data: horizonStaking.interface.encodeFunctionData('closeAllocation', [
          allocation.id,
          ZeroHash,
        ]),
        value: '0',
        description: `Close allocation ${allocation.id} (indexer: ${allocation.indexer.id}, ${formatGRT(allocation.allocatedTokens)} GRT)`,
      }))

      const batch: CalldataBatch = {
        timestamp: new Date().toISOString(),
        network: hre.network.name,
        chainId: hre.network.config.chainId!,
        entries,
      }

      const filePath = writeCalldataBatch(batch, 'close-allocations', args.outputDir)
      printCalldataSummary(batch, 'Close Allocations')
      console.log(`\nCalldata written to: ${filePath}`)
      return
    }

    // Get signer - use impersonation on local networks, secure accounts on mainnet
    let signer: Signer
    if (isLocalNetwork(hre)) {
      // On local networks, use any hardhat signer (force close is permissionless for old allocations)
      const [defaultSigner] = await hre.ethers.getSigners()
      signer = defaultSigner
      console.log(`\nUsing local account: ${await signer.getAddress()} (impersonation mode)`)
    } else {
      // On mainnet, use secure accounts
      signer = await graph.accounts.getDeployer(args.accountIndex)
      console.log(`\nUsing account: ${await signer.getAddress()}`)
    }

    const signerAddress = await signer.getAddress()
    const balance = await hre.ethers.provider.getBalance(signerAddress)
    console.log(`Account balance: ${hre.ethers.formatEther(balance)} ETH`)

    if (balance === 0n && !args.dryRun) {
      throw new Error('Account has no ETH balance')
    }

    // Execute transactions
    console.log('\nClosing allocations...')
    const results: CloseAllocationResult[] = []

    for (let i = 0; i < allocations.length; i++) {
      const allocation = allocations[i]
      console.log(`[${i + 1}/${allocations.length}] Closing ${allocation.id}...`)

      if (args.dryRun) {
        console.log(`  [DRY RUN] Would close allocation for indexer ${allocation.indexer.id}`)
        results.push({
          success: true,
          allocationId: allocation.id,
          indexer: allocation.indexer.id,
        })
        continue
      }

      try {
        const tx = await horizonStaking.connect(signer).closeAllocation(allocation.id, ZeroHash)
        const receipt = await tx.wait()

        results.push({
          success: true,
          txHash: receipt!.hash,
          gasUsed: receipt!.gasUsed,
          allocationId: allocation.id,
          indexer: allocation.indexer.id,
        })

        console.log(`  Success: ${receipt!.hash}`)
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        results.push({
          success: false,
          error: errorMessage,
          allocationId: allocation.id,
          indexer: allocation.indexer.id,
        })
        console.log(`  Failed: ${errorMessage}`)
      }
    }

    // Generate and write execution report
    const report = generateExecutionReport(
      results,
      args.dryRun ? 'dry-run' : 'execute',
      hre.network.name,
      hre.network.config.chainId!,
      'ops:allocations:close',
    )

    const filePath = writeExecutionReport(report, 'close-allocations', args.outputDir)
    printExecutionSummary(report, 'Close Allocations')
    console.log(`\nResults written to: ${filePath}`)
  })

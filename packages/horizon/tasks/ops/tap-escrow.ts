/**
 * TAP Escrow Operational Tasks
 *
 * Tasks for querying, thawing, and withdrawing funds from the TAP v1 Escrow contract
 * after Horizon migration.
 */

import { task, types, vars } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { Signer } from 'ethers'

import { getImpersonatedSigner, isLocalNetwork } from './lib/fork-utils'
import {
  formatGRT,
  generateEscrowReport,
  generateExecutionReport,
  loadEscrowAccountsFromFile,
  printCalldataSummary,
  printEscrowSummary,
  printExecutionSummary,
  writeCalldataBatch,
  writeEscrowReport,
  writeExecutionReport,
} from './lib/report'
import { groupEscrowAccountsBySender, queryEscrowAccounts } from './lib/subgraph'
import {
  executeBatchThaw,
  executeBatchWithdraw,
  generateThawCalldata,
  generateWithdrawCalldata,
  getTapEscrowContract,
} from './lib/tap-escrow'
import type { CalldataBatch, EscrowAccount } from './lib/types'
import { DEFAULTS } from './lib/types'

// ============================================
// Query Escrow Accounts Task
// ============================================

task('ops:escrow:query', 'Query and report TAP escrow accounts from TAP subgraph')
  .addOptionalParam(
    'subgraphApiKey',
    'API key for The Graph Network gateway (can also use SUBGRAPH_API_KEY hardhat var)',
    undefined,
    types.string,
  )
  .addOptionalParam(
    'senderAddresses',
    'Comma-separated list of sender addresses to query',
    DEFAULTS.SENDER_ADDRESSES.join(','),
    types.string,
  )
  .addOptionalParam(
    'excludedReceivers',
    'Comma-separated list of receiver addresses to exclude',
    DEFAULTS.UPGRADE_INDEXER,
    types.string,
  )
  .addOptionalParam('outputDir', 'Output directory for reports', DEFAULTS.OUTPUT_DIR, types.string)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    console.log('\n========== Query TAP Escrow Accounts ==========')

    // Get API key from args or hardhat vars
    let apiKey = args.subgraphApiKey
    if (!apiKey) {
      if (!vars.has('SUBGRAPH_API_KEY')) {
        throw new Error('No subgraph API key provided. Set --subgraph-api-key or use `npx hardhat vars set SUBGRAPH_API_KEY`')
      }
      apiKey = vars.get('SUBGRAPH_API_KEY')
    }

    // Parse sender addresses
    const senderAddresses = args.senderAddresses
      .split(',')
      .map((addr: string) => addr.trim().toLowerCase())
      .filter((addr: string) => addr.length > 0)

    // Parse excluded receivers
    const excludedReceivers = args.excludedReceivers
      .split(',')
      .map((addr: string) => addr.trim().toLowerCase())
      .filter((addr: string) => addr.length > 0)

    console.log(`Network: ${hre.network.name}`)
    console.log(`Chain ID: ${hre.network.config.chainId}`)
    console.log(`Sender Addresses: ${senderAddresses.join(', ')}`)
    console.log(`Excluded Receivers: ${excludedReceivers.join(', ')}`)
    console.log('')

    // Query subgraph
    console.log('Querying TAP subgraph for escrow accounts...')
    const accounts = await queryEscrowAccounts(apiKey, senderAddresses, excludedReceivers)

    if (accounts.length === 0) {
      console.log('No escrow accounts found with balance > 0.')
      return
    }

    // Group by sender for summary
    const summaryBySender = groupEscrowAccountsBySender(accounts)

    // Generate and write report
    const report = generateEscrowReport(
      accounts,
      summaryBySender,
      senderAddresses,
      excludedReceivers,
      hre.network.name,
      hre.network.config.chainId!,
    )

    const { jsonPath, csvPath } = writeEscrowReport(report, args.outputDir)

    // Print summary
    printEscrowSummary(report)

    console.log('\nReports written to:')
    console.log(`  JSON: ${jsonPath}`)
    console.log(`  CSV:  ${csvPath}`)
  })

// ============================================
// Thaw Escrow Task
// ============================================

task('ops:escrow:thaw', 'Initiate thawing for TAP escrow accounts')
  .addOptionalParam(
    'inputFile',
    'JSON file with escrow accounts (from ops:escrow:query). If not provided, queries subgraph.',
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
    'senderAddresses',
    'Comma-separated list of sender addresses to query',
    DEFAULTS.SENDER_ADDRESSES.join(','),
    types.string,
  )
  .addOptionalParam(
    'excludedReceivers',
    'Comma-separated list of receiver addresses to exclude',
    DEFAULTS.UPGRADE_INDEXER,
    types.string,
  )
  .addOptionalParam('limit', 'Maximum number of accounts to thaw (0 = all)', 0, types.int)
  .addOptionalParam('accountIndex', 'Derivation path index for the gateway account', 0, types.int)
  .addOptionalParam('escrowAddress', 'TAP Escrow contract address', DEFAULTS.TAP_ESCROW, types.string)
  .addOptionalParam('outputDir', 'Output directory for reports', DEFAULTS.OUTPUT_DIR, types.string)
  .addFlag('calldataOnly', 'Generate calldata without executing transactions')
  .addFlag('dryRun', 'Simulate without executing transactions')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    console.log('\n========== Thaw TAP Escrow Accounts ==========')
    console.log(`Network: ${hre.network.name}`)
    console.log(`Chain ID: ${hre.network.config.chainId}`)
    console.log(`Mode: ${args.calldataOnly ? 'Calldata Only' : args.dryRun ? 'Dry Run' : 'Execute'}`)
    console.log(`Escrow Contract: ${args.escrowAddress}`)

    // Get escrow accounts either from file or subgraph
    let accounts: EscrowAccount[]

    if (args.inputFile) {
      console.log(`Loading escrow accounts from: ${args.inputFile}`)
      accounts = loadEscrowAccountsFromFile(args.inputFile)
    } else {
      // Query subgraph
      let apiKey = args.subgraphApiKey
      if (!apiKey) {
        if (!vars.has('SUBGRAPH_API_KEY')) {
          throw new Error('No subgraph API key provided. Set --subgraph-api-key or use `npx hardhat vars set SUBGRAPH_API_KEY`')
        }
        apiKey = vars.get('SUBGRAPH_API_KEY')
      }

      const senderAddresses = args.senderAddresses
        .split(',')
        .map((addr: string) => addr.trim().toLowerCase())
        .filter((addr: string) => addr.length > 0)

      const excludedReceivers = args.excludedReceivers
        .split(',')
        .map((addr: string) => addr.trim().toLowerCase())
        .filter((addr: string) => addr.length > 0)

      console.log('Querying subgraph for escrow accounts...')
      accounts = await queryEscrowAccounts(apiKey, senderAddresses, excludedReceivers)
    }

    // Filter to accounts that have thawable balance
    let thawableAccounts = accounts.filter((a) => a.balance > a.amountThawing)

    if (thawableAccounts.length === 0) {
      console.log('No accounts with thawable balance found.')
      return
    }

    // Apply limit if specified (accounts are sorted by balance descending)
    if (args.limit > 0 && thawableAccounts.length > args.limit) {
      console.log(`Limiting to first ${args.limit} accounts (of ${thawableAccounts.length} total)`)
      thawableAccounts = thawableAccounts.slice(0, args.limit)
    }

    const totalThawable = thawableAccounts.reduce(
      (sum, a) => sum + (a.balance - a.amountThawing),
      0n,
    )

    console.log(`\nFound ${thawableAccounts.length} accounts with thawable balance`)
    console.log(`Total thawable GRT: ${formatGRT(totalThawable)}`)

    // Calldata-only mode
    if (args.calldataOnly) {
      const entries = generateThawCalldata(thawableAccounts, args.escrowAddress)

      const batch: CalldataBatch = {
        timestamp: new Date().toISOString(),
        network: hre.network.name,
        chainId: hre.network.config.chainId!,
        entries,
      }

      const filePath = writeCalldataBatch(batch, 'thaw-escrow', args.outputDir)
      printCalldataSummary(batch, 'Thaw Escrow')
      console.log(`\nCalldata written to: ${filePath}`)
      return
    }

    // Group accounts by sender for impersonation
    const accountsBySender = new Map<string, EscrowAccount[]>()
    for (const account of thawableAccounts) {
      const sender = account.sender.toLowerCase()
      if (!accountsBySender.has(sender)) {
        accountsBySender.set(sender, [])
      }
      accountsBySender.get(sender)!.push(account)
    }

    // Execute transactions grouped by sender
    console.log('\nThawing escrow accounts...')
    const results: Awaited<ReturnType<typeof executeBatchThaw>> = []
    let totalProcessed = 0

    for (const [senderAddress, senderAccounts] of accountsBySender) {
      // Get signer for this sender
      let signer: Signer
      if (isLocalNetwork(hre)) {
        // On local networks, impersonate the sender address
        console.log(`\nImpersonating sender: ${senderAddress}`)
        signer = await getImpersonatedSigner(hre, senderAddress)
      } else {
        // On mainnet, use secure accounts
        const graph = hre.graph()
        signer = await graph.accounts.getGateway(args.accountIndex)
        const signerAddress = await signer.getAddress()
        if (signerAddress.toLowerCase() !== senderAddress) {
          console.log(`Warning: Gateway address ${signerAddress} does not match sender ${senderAddress}`)
        }
      }

      const signerAddress = await signer.getAddress()
      const balance = await hre.ethers.provider.getBalance(signerAddress)
      console.log(`Using account: ${signerAddress} (balance: ${hre.ethers.formatEther(balance)} ETH)`)

      if (balance === 0n && !args.dryRun && !isLocalNetwork(hre)) {
        throw new Error('Account has no ETH balance')
      }

      // Get TAP Escrow contract with this signer
      const escrowContract = getTapEscrowContract(signer, args.escrowAddress)

      // Execute batch for this sender
      const senderResults = await executeBatchThaw(
        escrowContract,
        senderAccounts,
        args.dryRun,
        (current, total, result) => {
          totalProcessed++
          if (result.success) {
            console.log(`[${totalProcessed}/${thawableAccounts.length}] Thawed ${formatGRT(result.amount)} GRT for ${result.receiver}`)
          } else {
            console.log(`[${totalProcessed}/${thawableAccounts.length}] Failed for ${result.receiver}: ${result.error}`)
          }
        },
      )

      results.push(...senderResults)
    }

    // Generate and write execution report
    const report = generateExecutionReport(
      results,
      args.dryRun ? 'dry-run' : 'execute',
      hre.network.name,
      hre.network.config.chainId!,
      'ops:escrow:thaw',
    )

    const filePath = writeExecutionReport(report, 'thaw-escrow', args.outputDir)
    printExecutionSummary(report, 'Thaw Escrow')
    console.log(`\nResults written to: ${filePath}`)

    // Print thaw end timestamp for successful thaws
    const successfulThaws = results.filter((r) => r.success && r.thawEndTimestamp)
    if (successfulThaws.length > 0 && !args.dryRun) {
      const thawEndDate = new Date(Number(successfulThaws[0].thawEndTimestamp) * 1000)
      console.log(`\nThaw period ends: ${thawEndDate.toISOString()}`)
      console.log('Run ops:escrow:withdraw after this date to complete withdrawal.')
    }
  })

// ============================================
// Withdraw Escrow Task
// ============================================

task('ops:escrow:withdraw', 'Withdraw thawed funds from TAP escrow accounts')
  .addOptionalParam(
    'inputFile',
    'JSON file with escrow accounts (from ops:escrow:query). If not provided, queries subgraph.',
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
    'senderAddresses',
    'Comma-separated list of sender addresses to query',
    DEFAULTS.SENDER_ADDRESSES.join(','),
    types.string,
  )
  .addOptionalParam(
    'excludedReceivers',
    'Comma-separated list of receiver addresses to exclude',
    DEFAULTS.UPGRADE_INDEXER,
    types.string,
  )
  .addOptionalParam('limit', 'Maximum number of accounts to withdraw (0 = all)', 0, types.int)
  .addOptionalParam('accountIndex', 'Derivation path index for the gateway account', 0, types.int)
  .addOptionalParam('escrowAddress', 'TAP Escrow contract address', DEFAULTS.TAP_ESCROW, types.string)
  .addOptionalParam('outputDir', 'Output directory for reports', DEFAULTS.OUTPUT_DIR, types.string)
  .addFlag('calldataOnly', 'Generate calldata without executing transactions')
  .addFlag('dryRun', 'Simulate without executing transactions')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    console.log('\n========== Withdraw TAP Escrow Accounts ==========')
    console.log(`Network: ${hre.network.name}`)
    console.log(`Chain ID: ${hre.network.config.chainId}`)
    console.log(`Mode: ${args.calldataOnly ? 'Calldata Only' : args.dryRun ? 'Dry Run' : 'Execute'}`)
    console.log(`Escrow Contract: ${args.escrowAddress}`)

    // Get escrow accounts either from file or subgraph
    let accounts: EscrowAccount[]

    if (args.inputFile) {
      console.log(`Loading escrow accounts from: ${args.inputFile}`)
      accounts = loadEscrowAccountsFromFile(args.inputFile)
    } else {
      // Query subgraph
      let apiKey = args.subgraphApiKey
      if (!apiKey) {
        if (!vars.has('SUBGRAPH_API_KEY')) {
          throw new Error('No subgraph API key provided. Set --subgraph-api-key or use `npx hardhat vars set SUBGRAPH_API_KEY`')
        }
        apiKey = vars.get('SUBGRAPH_API_KEY')
      }

      const senderAddresses = args.senderAddresses
        .split(',')
        .map((addr: string) => addr.trim().toLowerCase())
        .filter((addr: string) => addr.length > 0)

      const excludedReceivers = args.excludedReceivers
        .split(',')
        .map((addr: string) => addr.trim().toLowerCase())
        .filter((addr: string) => addr.length > 0)

      console.log('Querying subgraph for escrow accounts...')
      accounts = await queryEscrowAccounts(apiKey, senderAddresses, excludedReceivers)
    }

    // Filter to accounts that have completed thawing
    const now = BigInt(Math.floor(Date.now() / 1000))
    let withdrawableAccounts = accounts.filter(
      (a) => a.thawEndTimestamp > 0n && a.thawEndTimestamp <= now,
    )

    if (withdrawableAccounts.length === 0) {
      console.log('\nNo accounts ready for withdrawal.')

      // Show accounts that are still thawing
      const stillThawing = accounts.filter((a) => a.thawEndTimestamp > now)
      if (stillThawing.length > 0) {
        console.log('\nAccounts still thawing:')
        for (const account of stillThawing.slice(0, 5)) {
          const thawEndDate = new Date(Number(account.thawEndTimestamp) * 1000)
          console.log(`  ${account.receiver}: thaw ends ${thawEndDate.toISOString()}`)
        }
        if (stillThawing.length > 5) {
          console.log(`  ... and ${stillThawing.length - 5} more`)
        }
      }

      // Show accounts that haven't started thawing
      const notThawing = accounts.filter((a) => a.thawEndTimestamp === 0n && a.balance > 0n)
      if (notThawing.length > 0) {
        console.log(`\n${notThawing.length} accounts have not started thawing. Run ops:escrow:thaw first.`)
      }

      return
    }

    // Apply limit if specified
    if (args.limit > 0 && withdrawableAccounts.length > args.limit) {
      console.log(`Limiting to first ${args.limit} accounts (of ${withdrawableAccounts.length} total)`)
      withdrawableAccounts = withdrawableAccounts.slice(0, args.limit)
    }

    const totalWithdrawable = withdrawableAccounts.reduce((sum, a) => sum + a.amountThawing, 0n)

    console.log(`\nFound ${withdrawableAccounts.length} accounts ready for withdrawal`)
    console.log(`Total withdrawable GRT: ${formatGRT(totalWithdrawable)}`)

    // Calldata-only mode
    if (args.calldataOnly) {
      const entries = generateWithdrawCalldata(withdrawableAccounts, args.escrowAddress)

      const batch: CalldataBatch = {
        timestamp: new Date().toISOString(),
        network: hre.network.name,
        chainId: hre.network.config.chainId!,
        entries,
      }

      const filePath = writeCalldataBatch(batch, 'withdraw-escrow', args.outputDir)
      printCalldataSummary(batch, 'Withdraw Escrow')
      console.log(`\nCalldata written to: ${filePath}`)
      return
    }

    // Group accounts by sender for impersonation
    const accountsBySender = new Map<string, EscrowAccount[]>()
    for (const account of withdrawableAccounts) {
      const sender = account.sender.toLowerCase()
      if (!accountsBySender.has(sender)) {
        accountsBySender.set(sender, [])
      }
      accountsBySender.get(sender)!.push(account)
    }

    // Execute transactions grouped by sender
    console.log('\nWithdrawing escrow accounts...')
    const results: Awaited<ReturnType<typeof executeBatchWithdraw>> = []
    let totalProcessed = 0

    for (const [senderAddress, senderAccounts] of accountsBySender) {
      // Get signer for this sender
      let signer: Signer
      if (isLocalNetwork(hre)) {
        // On local networks, impersonate the sender address
        console.log(`\nImpersonating sender: ${senderAddress}`)
        signer = await getImpersonatedSigner(hre, senderAddress)
      } else {
        // On mainnet, use secure accounts
        const graph = hre.graph()
        signer = await graph.accounts.getGateway(args.accountIndex)
        const signerAddress = await signer.getAddress()
        if (signerAddress.toLowerCase() !== senderAddress) {
          console.log(`Warning: Gateway address ${signerAddress} does not match sender ${senderAddress}`)
        }
      }

      const signerAddress = await signer.getAddress()
      const balance = await hre.ethers.provider.getBalance(signerAddress)
      console.log(`Using account: ${signerAddress} (balance: ${hre.ethers.formatEther(balance)} ETH)`)

      if (balance === 0n && !args.dryRun && !isLocalNetwork(hre)) {
        throw new Error('Account has no ETH balance')
      }

      // Get TAP Escrow contract with this signer
      const escrowContract = getTapEscrowContract(signer, args.escrowAddress)

      // Execute batch for this sender
      const senderResults = await executeBatchWithdraw(
        escrowContract,
        senderAccounts,
        args.dryRun,
        (current, total, result) => {
          totalProcessed++
          if (result.success) {
            console.log(`[${totalProcessed}/${withdrawableAccounts.length}] Withdrew ~${formatGRT(result.amount)} GRT for ${result.receiver}`)
          } else {
            console.log(`[${totalProcessed}/${withdrawableAccounts.length}] Failed for ${result.receiver}: ${result.error}`)
          }
        },
      )

      results.push(...senderResults)
    }

    // Generate and write execution report
    const report = generateExecutionReport(
      results,
      args.dryRun ? 'dry-run' : 'execute',
      hre.network.name,
      hre.network.config.chainId!,
      'ops:escrow:withdraw',
    )

    const filePath = writeExecutionReport(report, 'withdraw-escrow', args.outputDir)
    printExecutionSummary(report, 'Withdraw Escrow')
    console.log(`\nResults written to: ${filePath}`)

    // Print total withdrawn
    const totalWithdrawn = results
      .filter((r) => r.success)
      .reduce((sum, r) => sum + r.amount, 0n)
    console.log(`\nTotal GRT withdrawn: ${formatGRT(totalWithdrawn)}`)
  })

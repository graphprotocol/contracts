/**
 * Verification tasks for fork testing operations
 *
 * These tasks verify that state changes have been applied correctly by
 * reading on-chain state directly (not from subgraph).
 */

import * as fs from 'fs'
import { task, types } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import { formatGRT } from './lib/report'
import { getTapEscrowContract } from './lib/tap-escrow'
import type {
  CloseAllocationResult,
  EscrowAccount,
  EscrowReport,
  ExecutionReport,
  ThawResult,
  WithdrawResult,
} from './lib/types'
import { DEFAULTS } from './lib/types'

// ============================================
// Allocation State Enum (from HorizonStaking)
// ============================================

enum AllocationState {
  Null,
  Active,
  Closed,
  Finalized,
}

// ============================================
// Verification Task
// ============================================

task('ops:verify', 'Verify state changes after ops tasks')
  .addParam('type', 'Verification type: allocations, escrow-thaw, escrow-withdraw', undefined, types.string)
  .addParam('inputFile', 'JSON file with execution results (from close/thaw/withdraw task output)', undefined, types.string)
  .addOptionalParam('originalFile', 'Original escrow accounts file (required for escrow-withdraw)', undefined, types.string)
  .addOptionalParam('escrowAddress', 'TAP Escrow contract address', DEFAULTS.TAP_ESCROW, types.string)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    console.log(`\n========== Verify: ${args.type} ==========`)
    console.log(`Network: ${hre.network.name}`)
    console.log(`Input file: ${args.inputFile}`)

    // Load input file
    const content = fs.readFileSync(args.inputFile, 'utf-8')

    switch (args.type) {
      case 'allocations':
        await verifyAllocations(hre, content)
        break
      case 'escrow-thaw':
        await verifyEscrowThaw(hre, content, args.escrowAddress)
        break
      case 'escrow-withdraw':
        if (!args.originalFile) {
          throw new Error('--original-file is required for escrow-withdraw verification')
        }
        await verifyEscrowWithdraw(hre, content, args.originalFile, args.escrowAddress)
        break
      default:
        throw new Error(`Unknown verification type: ${args.type}. Valid types: allocations, escrow-thaw, escrow-withdraw`)
    }
  })

// ============================================
// Allocation Verification
// ============================================

async function verifyAllocations(
  hre: HardhatRuntimeEnvironment,
  content: string,
): Promise<void> {
  const report = JSON.parse(content) as ExecutionReport<CloseAllocationResult>

  // Only verify successful operations
  const successfulOps = report.results.filter((r) => r.success)
  if (successfulOps.length === 0) {
    console.log('No successful operations to verify.')
    return
  }

  console.log(`\nVerifying ${successfulOps.length} closed allocations...`)

  const graph = hre.graph()
  const horizonStaking = graph.horizon.contracts.HorizonStaking

  let verified = 0
  let failed = 0

  for (const result of successfulOps) {
    try {
      const state = await horizonStaking.getAllocationState(result.allocationId)

      if (state === BigInt(AllocationState.Closed) || state === BigInt(AllocationState.Finalized)) {
        verified++
        console.log(`  [OK] ${result.allocationId} - State: ${AllocationState[Number(state)]}`)
      } else {
        failed++
        console.log(`  [FAIL] ${result.allocationId} - Expected Closed/Finalized, got: ${AllocationState[Number(state)]}`)
      }
    } catch (error) {
      failed++
      const errorMessage = error instanceof Error ? error.message : String(error)
      console.log(`  [ERROR] ${result.allocationId} - ${errorMessage}`)
    }
  }

  console.log(`\nVerification complete: ${verified} verified, ${failed} failed`)

  if (failed > 0) {
    throw new Error(`Verification failed for ${failed} allocations`)
  }

  console.log('All allocations verified as Closed!')
}

// ============================================
// Escrow Thaw Verification
// ============================================

async function verifyEscrowThaw(
  hre: HardhatRuntimeEnvironment,
  content: string,
  escrowAddress: string,
): Promise<void> {
  const report = JSON.parse(content) as ExecutionReport<ThawResult>

  // Only verify successful operations
  const successfulOps = report.results.filter((r) => r.success)
  if (successfulOps.length === 0) {
    console.log('No successful operations to verify.')
    return
  }

  console.log(`\nVerifying ${successfulOps.length} thawed escrow accounts...`)

  // Get a signer for reading contract state
  const [signer] = await hre.ethers.getSigners()
  const escrowContract = getTapEscrowContract(signer, escrowAddress)

  let verified = 0
  let failed = 0

  for (const result of successfulOps) {
    try {
      const account = await escrowContract.escrowAccounts(result.sender, result.receiver)
      const thawEndTimestamp = account[2] // [balance, amountThawing, thawEndTimestamp]

      if (thawEndTimestamp > 0n) {
        verified++
        const thawEndDate = new Date(Number(thawEndTimestamp) * 1000)
        console.log(`  [OK] ${result.receiver} - Thaw ends: ${thawEndDate.toISOString()}`)
      } else {
        failed++
        console.log(`  [FAIL] ${result.receiver} - thawEndTimestamp is 0`)
      }
    } catch (error) {
      failed++
      const errorMessage = error instanceof Error ? error.message : String(error)
      console.log(`  [ERROR] ${result.receiver} - ${errorMessage}`)
    }
  }

  console.log(`\nVerification complete: ${verified} verified, ${failed} failed`)

  if (failed > 0) {
    throw new Error(`Verification failed for ${failed} escrow accounts`)
  }

  console.log('All accounts verified with thaw in progress!')
}

// ============================================
// Escrow Withdraw Verification
// ============================================

async function verifyEscrowWithdraw(
  hre: HardhatRuntimeEnvironment,
  content: string,
  originalFilePath: string,
  escrowAddress: string,
): Promise<void> {
  const report = JSON.parse(content) as ExecutionReport<WithdrawResult>

  // Only verify successful operations
  const successfulOps = report.results.filter((r) => r.success)
  if (successfulOps.length === 0) {
    console.log('No successful operations to verify.')
    return
  }

  // Load original balances from the query file
  const originalContent = fs.readFileSync(originalFilePath, 'utf-8')
  const originalReport = JSON.parse(originalContent) as EscrowReport

  // Create a map of original balances
  const originalBalances = new Map<string, bigint>()
  for (const account of originalReport.accounts) {
    // Key by sender-receiver pair
    const key = `${account.sender.toLowerCase()}-${account.receiver.toLowerCase()}`
    originalBalances.set(key, BigInt(account.balance as unknown as string))
  }

  console.log(`\nVerifying ${successfulOps.length} withdrawn escrow accounts...`)

  // Get a signer for reading contract state
  const [signer] = await hre.ethers.getSigners()
  const escrowContract = getTapEscrowContract(signer, escrowAddress)

  let verified = 0
  let failed = 0

  for (const result of successfulOps) {
    try {
      const key = `${result.sender.toLowerCase()}-${result.receiver.toLowerCase()}`
      const originalBalance = originalBalances.get(key)

      if (!originalBalance) {
        console.log(`  [WARN] ${result.receiver} - Original balance not found in query file`)
        continue
      }

      const account = await escrowContract.escrowAccounts(result.sender, result.receiver)
      const currentBalance = account[0] // [balance, amountThawing, thawEndTimestamp]

      if (currentBalance < originalBalance) {
        verified++
        const withdrawn = originalBalance - currentBalance
        console.log(`  [OK] ${result.receiver} - Withdrew ${formatGRT(withdrawn)} GRT (${formatGRT(originalBalance)} -> ${formatGRT(currentBalance)})`)
      } else {
        failed++
        console.log(`  [FAIL] ${result.receiver} - Balance not reduced (${formatGRT(originalBalance)} -> ${formatGRT(currentBalance)})`)
      }
    } catch (error) {
      failed++
      const errorMessage = error instanceof Error ? error.message : String(error)
      console.log(`  [ERROR] ${result.receiver} - ${errorMessage}`)
    }
  }

  console.log(`\nVerification complete: ${verified} verified, ${failed} failed`)

  if (failed > 0) {
    throw new Error(`Verification failed for ${failed} escrow accounts`)
  }

  console.log('All accounts verified with reduced balance!')
}

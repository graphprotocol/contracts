/**
 * TAP Escrow contract utilities for TAP Escrow Recovery operations
 *
 * Note: This is for the TAP v1 Escrow contract, which has a different interface
 * than the Horizon PaymentsEscrow (v2). The v1 contract uses sender-receiver pairs
 * while v2 uses payer-collector-receiver tuples.
 */

import type { Signer } from 'ethers'
import { Contract, Interface } from 'ethers'

import type { CalldataEntry, EscrowAccount, ThawResult, WithdrawResult } from './types'
import { DEFAULTS } from './types'

// ============================================
// TAP Escrow v1 Contract ABI
// ============================================

/**
 * Minimal ABI for TAP Escrow v1 contract interactions
 * Address: 0x8f477709eF277d4A880801D01A140a9CF88bA0d3 (Arbitrum One)
 */
const TAP_ESCROW_V1_ABI = [
  // State changing functions
  'function thaw(address receiver, uint256 amount) external',
  'function withdraw(address receiver) external',

  // View functions
  'function escrowAccounts(address sender, address receiver) external view returns (uint256 balance, uint256 amountThawing, uint256 thawEndTimestamp)',
  'function withdrawEscrowThawingPeriod() external view returns (uint256)',
] as const

// ============================================
// Contract Interface
// ============================================

/**
 * Get TAP Escrow v1 contract interface for calldata encoding
 */
export function getTapEscrowInterface(): Interface {
  return new Interface(TAP_ESCROW_V1_ABI)
}

/**
 * Create TAP Escrow v1 contract instance
 */
export function getTapEscrowContract(signer: Signer, address?: string): Contract {
  return new Contract(address ?? DEFAULTS.TAP_ESCROW, TAP_ESCROW_V1_ABI, signer)
}

// ============================================
// Calldata Generation
// ============================================

/**
 * Generate calldata for thawing escrow funds
 */
export function encodeThawCalldata(receiver: string, amount: bigint): string {
  const iface = getTapEscrowInterface()
  return iface.encodeFunctionData('thaw', [receiver, amount])
}

/**
 * Generate calldata for withdrawing escrow funds
 */
export function encodeWithdrawCalldata(receiver: string): string {
  const iface = getTapEscrowInterface()
  return iface.encodeFunctionData('withdraw', [receiver])
}

/**
 * Generate calldata entries for batch thaw operations
 */
export function generateThawCalldata(
  accounts: EscrowAccount[],
  escrowAddress: string = DEFAULTS.TAP_ESCROW,
): CalldataEntry[] {
  return accounts.map((account) => {
    // Thaw the available balance (balance - amountThawing)
    const amountToThaw = account.balance - account.amountThawing
    if (amountToThaw <= 0n) {
      return {
        to: escrowAddress,
        data: '',
        value: '0',
        description: `Skip ${account.receiver} - already thawing or no balance`,
      }
    }

    return {
      to: escrowAddress,
      data: encodeThawCalldata(account.receiver, amountToThaw),
      value: '0',
      description: `Thaw ${formatGRT(amountToThaw)} GRT for receiver ${account.receiver}`,
    }
  }).filter((entry) => entry.data !== '')
}

/**
 * Generate calldata entries for batch withdraw operations
 */
export function generateWithdrawCalldata(
  accounts: EscrowAccount[],
  escrowAddress: string = DEFAULTS.TAP_ESCROW,
): CalldataEntry[] {
  const now = BigInt(Math.floor(Date.now() / 1000))

  return accounts.filter((account) => {
    // Only include accounts that have completed thawing
    return account.thawEndTimestamp > 0n && account.thawEndTimestamp <= now
  }).map((account) => ({
    to: escrowAddress,
    data: encodeWithdrawCalldata(account.receiver),
    value: '0',
    description: `Withdraw thawed funds for receiver ${account.receiver}`,
  }))
}

// ============================================
// Transaction Execution
// ============================================

/**
 * Execute thaw transaction for a single escrow account
 */
export async function executeThaw(
  contract: Contract,
  account: EscrowAccount,
  dryRun: boolean = false,
): Promise<ThawResult> {
  const amountToThaw = account.balance - account.amountThawing
  if (amountToThaw <= 0n) {
    return {
      success: false,
      sender: account.sender,
      receiver: account.receiver,
      amount: 0n,
      error: 'No balance available to thaw',
    }
  }

  if (dryRun) {
    console.log(`[DRY RUN] Would thaw ${formatGRT(amountToThaw)} GRT for receiver ${account.receiver}`)
    return {
      success: true,
      sender: account.sender,
      receiver: account.receiver,
      amount: amountToThaw,
    }
  }

  try {
    const tx = await contract.thaw(account.receiver, amountToThaw)
    const receipt = await tx.wait()

    // Calculate thaw end timestamp (30 days from now)
    const thawingPeriod = await contract.withdrawEscrowThawingPeriod()
    const thawEndTimestamp = BigInt(Math.floor(Date.now() / 1000)) + thawingPeriod

    return {
      success: true,
      txHash: receipt.hash,
      gasUsed: receipt.gasUsed,
      sender: account.sender,
      receiver: account.receiver,
      amount: amountToThaw,
      thawEndTimestamp,
    }
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
      sender: account.sender,
      receiver: account.receiver,
      amount: amountToThaw,
    }
  }
}

/**
 * Execute withdraw transaction for a single escrow account
 */
export async function executeWithdraw(
  contract: Contract,
  account: EscrowAccount,
  dryRun: boolean = false,
): Promise<WithdrawResult> {
  const now = BigInt(Math.floor(Date.now() / 1000))

  if (account.thawEndTimestamp === 0n) {
    return {
      success: false,
      sender: account.sender,
      receiver: account.receiver,
      amount: 0n,
      error: 'No thawing in progress',
    }
  }

  if (account.thawEndTimestamp > now) {
    return {
      success: false,
      sender: account.sender,
      receiver: account.receiver,
      amount: 0n,
      error: `Still thawing until ${new Date(Number(account.thawEndTimestamp) * 1000).toISOString()}`,
    }
  }

  const withdrawableAmount = account.amountThawing < account.balance
    ? account.amountThawing
    : account.balance

  if (dryRun) {
    console.log(`[DRY RUN] Would withdraw ~${formatGRT(withdrawableAmount)} GRT for receiver ${account.receiver}`)
    return {
      success: true,
      sender: account.sender,
      receiver: account.receiver,
      amount: withdrawableAmount,
    }
  }

  try {
    const tx = await contract.withdraw(account.receiver)
    const receipt = await tx.wait()

    return {
      success: true,
      txHash: receipt.hash,
      gasUsed: receipt.gasUsed,
      sender: account.sender,
      receiver: account.receiver,
      amount: withdrawableAmount,
    }
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
      sender: account.sender,
      receiver: account.receiver,
      amount: withdrawableAmount,
    }
  }
}

/**
 * Execute batch thaw operations
 */
export async function executeBatchThaw(
  contract: Contract,
  accounts: EscrowAccount[],
  dryRun: boolean = false,
  onProgress?: (current: number, total: number, result: ThawResult) => void,
): Promise<ThawResult[]> {
  const results: ThawResult[] = []

  for (let i = 0; i < accounts.length; i++) {
    const result = await executeThaw(contract, accounts[i], dryRun)
    results.push(result)
    onProgress?.(i + 1, accounts.length, result)
  }

  return results
}

/**
 * Execute batch withdraw operations
 */
export async function executeBatchWithdraw(
  contract: Contract,
  accounts: EscrowAccount[],
  dryRun: boolean = false,
  onProgress?: (current: number, total: number, result: WithdrawResult) => void,
): Promise<WithdrawResult[]> {
  const results: WithdrawResult[] = []

  for (let i = 0; i < accounts.length; i++) {
    const result = await executeWithdraw(contract, accounts[i], dryRun)
    results.push(result)
    onProgress?.(i + 1, accounts.length, result)
  }

  return results
}

// ============================================
// Helpers
// ============================================

/**
 * Format GRT amount for display (18 decimals)
 */
function formatGRT(amount: bigint): string {
  const decimals = 18n
  const divisor = 10n ** decimals
  const whole = amount / divisor
  const fraction = amount % divisor
  const fractionStr = fraction.toString().padStart(Number(decimals), '0').slice(0, 4)
  return `${whole.toLocaleString()}.${fractionStr}`
}

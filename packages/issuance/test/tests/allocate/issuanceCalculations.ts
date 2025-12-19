import { ethers } from 'hardhat'

/**
 * Shared calculation utilities for issuance tests.
 * These functions provide reference implementations for expected values in tests.
 */

// Constants for better readability
export const CALCULATION_CONSTANTS = {
  PRECISION_MULTIPLIER: 1000n, // For ratio calculations
  WEI_PER_ETHER: ethers.parseEther('1'),
} as const

/**
 * Calculate expected self-minting accumulation during pause.
 * In the new model, we accumulate self-minting (not allocator-minting) during pause.
 *
 * @param totalSelfMintingRate - Total self-minting rate (tokens per block)
 * @param blocks - Number of blocks to accumulate over
 * @returns Expected accumulated self-minting amount
 */
export function calculateExpectedSelfMintingAccumulation(totalSelfMintingRate: bigint, blocks: bigint): bigint {
  if (blocks === 0n || totalSelfMintingRate === 0n) return 0n
  return totalSelfMintingRate * blocks
}

/**
 * Calculate expected issuance for a specific target during normal operation.
 *
 * @param targetRate - Target's allocation rate (tokens per block)
 * @param blocks - Number of blocks
 * @returns Expected issuance for the target
 */
export function calculateExpectedTargetIssuance(targetRate: bigint, blocks: bigint): bigint {
  if (blocks === 0n || targetRate === 0n) return 0n
  return targetRate * blocks
}

/**
 * Calculate proportional distribution during unpause when insufficient funds.
 * Used when available funds < total non-default needs.
 *
 * @param availableAmount - Total available amount to distribute
 * @param targetRate - Target's allocator-minting rate (tokens per block)
 * @param totalNonDefaultRate - Total non-default allocator-minting rate
 * @returns Expected amount for the target
 */
export function calculateProportionalDistribution(
  availableAmount: bigint,
  targetRate: bigint,
  totalNonDefaultRate: bigint,
): bigint {
  if (availableAmount === 0n || targetRate === 0n || totalNonDefaultRate === 0n) return 0n
  return (availableAmount * targetRate) / totalNonDefaultRate
}

/**
 * Calculate expected total issuance for multiple targets.
 *
 * @param blocks - Number of blocks
 * @param targetRates - Array of target rates (tokens per block)
 * @returns Array of expected issuance amounts for each target
 */
export function calculateMultiTargetIssuance(blocks: bigint, targetRates: bigint[]): bigint[] {
  return targetRates.map((rate) => calculateExpectedTargetIssuance(rate, blocks))
}

/**
 * Verify that distributed amounts add up to expected total.
 *
 * @param distributedAmounts - Array of distributed amounts
 * @param expectedTotal - Expected total amount
 * @param tolerance - Tolerance for rounding errors (default: 1 wei)
 * @returns True if amounts add up within tolerance
 */
export function verifyTotalDistribution(
  distributedAmounts: bigint[],
  expectedTotal: bigint,
  tolerance: bigint = 1n,
): boolean {
  const totalDistributed = distributedAmounts.reduce((sum, amount) => sum + amount, 0n)
  const diff = totalDistributed > expectedTotal ? totalDistributed - expectedTotal : expectedTotal - totalDistributed
  return diff <= tolerance
}

/**
 * Calculate expected distribution ratios between targets
 *
 * @param rates - Array of rates (tokens per block)
 * @returns Array of ratios relative to first target
 */
export function calculateExpectedRatios(rates: bigint[]): bigint[] {
  if (rates.length === 0) return []

  const baseRate = rates[0]
  if (baseRate === 0n) return rates.map(() => 0n)

  return rates.map((rate) => (rate * CALCULATION_CONSTANTS.PRECISION_MULTIPLIER) / baseRate)
}

/**
 * Convert allocation percentage to absolute rate
 *
 * @param percentage - Percentage as a number (e.g., 30 for 30%)
 * @param issuancePerBlock - Total issuance per block
 * @returns Absolute rate (tokens per block)
 */
export function percentageToRate(percentage: number, issuancePerBlock: bigint): bigint {
  return (issuancePerBlock * BigInt(Math.round(percentage * 100))) / 10000n
}

/**
 * Convert rate to percentage
 *
 * @param rate - Rate (tokens per block)
 * @param issuancePerBlock - Total issuance per block
 * @returns Percentage as a number
 */
export function rateToPercentage(rate: bigint, issuancePerBlock: bigint): number {
  if (issuancePerBlock === 0n) return 0
  return Number((rate * 10000n) / issuancePerBlock) / 100
}

/**
 * Helper to convert ETH string to wei bigint.
 */
export function parseEther(value: string): bigint {
  return ethers.parseEther(value)
}

import { ethers } from 'hardhat'

/**
 * Shared calculation utilities for issuance tests.
 * These functions provide reference implementations for expected values in tests.
 * Enhanced with better naming, documentation, and error handling.
 */

// Constants for better readability
export const CALCULATION_CONSTANTS = {
  PPM_DENOMINATOR: 1_000_000n, // Parts per million denominator
  PRECISION_MULTIPLIER: 1000n, // For ratio calculations
  WEI_PER_ETHER: ethers.parseEther('1'),
} as const

/**
 * Calculate expected accumulation for allocator-minting targets during pause.
 * Accumulation happens from lastIssuanceAccumulationBlock to current block.
 *
 * @param issuancePerBlock - Issuance rate per block
 * @param blocks - Number of blocks to accumulate over
 * @param allocatorMintingPPM - Total allocator-minting allocation in PPM
 * @returns Expected accumulated amount for allocator-minting targets
 */
export function calculateExpectedAccumulation(
  issuancePerBlock: bigint,
  blocks: bigint,
  allocatorMintingPPM: bigint,
): bigint {
  if (blocks === 0n || allocatorMintingPPM === 0n) return 0n

  const totalIssuance = issuancePerBlock * blocks
  // Contract uses: totalIssuance * totalAllocatorMintingAllocationPPM / MILLION
  return (totalIssuance * allocatorMintingPPM) / CALCULATION_CONSTANTS.PPM_DENOMINATOR
}

/**
 * Calculate expected issuance for a specific target.
 *
 * @param issuancePerBlock - Issuance rate per block
 * @param blocks - Number of blocks
 * @param targetAllocationPPM - Target's allocation in PPM
 * @returns Expected issuance for the target
 */
export function calculateExpectedTargetIssuance(
  issuancePerBlock: bigint,
  blocks: bigint,
  targetAllocationPPM: bigint,
): bigint {
  if (blocks === 0n || targetAllocationPPM === 0n) return 0n

  const totalIssuance = issuancePerBlock * blocks
  return (totalIssuance * targetAllocationPPM) / CALCULATION_CONSTANTS.PPM_DENOMINATOR
}

/**
 * Calculate proportional distribution of pending issuance among allocator-minting targets.
 *
 * @param pendingAmount - Total pending amount to distribute
 * @param targetAllocationPPM - Target's allocator-minting allocation in PPM
 * @param totalSelfMintingPPM - Total self-minting allocation in PPM
 * @returns Expected amount for the target
 */
export function calculateProportionalDistribution(
  pendingAmount: bigint,
  targetAllocationPPM: bigint,
  totalSelfMintingPPM: bigint,
): bigint {
  if (pendingAmount === 0n || targetAllocationPPM === 0n) return 0n

  const totalAllocatorMintingPPM = CALCULATION_CONSTANTS.PPM_DENOMINATOR - totalSelfMintingPPM
  if (totalAllocatorMintingPPM === 0n) return 0n

  return (pendingAmount * targetAllocationPPM) / totalAllocatorMintingPPM
}

/**
 * Calculate expected total issuance for multiple targets.
 *
 * @param issuancePerBlock - Issuance rate per block
 * @param blocks - Number of blocks
 * @param targetAllocations - Array of target allocations in PPM
 * @returns Array of expected issuance amounts for each target
 */
export function calculateMultiTargetIssuance(
  issuancePerBlock: bigint,
  blocks: bigint,
  targetAllocations: bigint[],
): bigint[] {
  return targetAllocations.map((allocation) => calculateExpectedTargetIssuance(issuancePerBlock, blocks, allocation))
}

/**
 * Verify that distributed amounts add up to expected total rate.
 *
 * @param distributedAmounts - Array of distributed amounts
 * @param expectedTotalRate - Expected total issuance rate
 * @param blocks - Number of blocks
 * @param tolerance - Tolerance for rounding errors (default: 1 wei)
 * @returns True if amounts add up within tolerance
 */
export function verifyTotalDistribution(
  distributedAmounts: bigint[],
  expectedTotalRate: bigint,
  blocks: bigint,
  tolerance: bigint = 1n,
): boolean {
  const totalDistributed = distributedAmounts.reduce((sum, amount) => sum + amount, 0n)
  const expectedTotal = expectedTotalRate * blocks
  const diff = totalDistributed > expectedTotal ? totalDistributed - expectedTotal : expectedTotal - totalDistributed
  return diff <= tolerance
}

/**
 * Calculate expected distribution ratios between targets
 *
 * @param allocations - Array of allocations in PPM
 * @returns Array of ratios relative to first target
 */
export function calculateExpectedRatios(allocations: bigint[]): bigint[] {
  if (allocations.length === 0) return []

  const baseAllocation = allocations[0]
  if (baseAllocation === 0n) return allocations.map(() => 0n)

  return allocations.map((allocation) => (allocation * CALCULATION_CONSTANTS.PRECISION_MULTIPLIER) / baseAllocation)
}

/**
 * Convert allocation percentage to PPM
 *
 * @param percentage - Percentage as a number (e.g., 30 for 30%)
 * @returns PPM value
 */
export function percentageToPPM(percentage: number): number {
  return Math.round(percentage * 10_000) // 1% = 10,000 PPM
}

/**
 * Convert PPM to percentage
 *
 * @param ppm - PPM value
 * @returns Percentage as a number
 */
export function ppmToPercentage(ppm: bigint | number): number {
  return Number(ppm) / 10_000
}

/**
 * Helper to convert ETH string to wei bigint.
 */
export function parseEther(value: string): bigint {
  return ethers.parseEther(value)
}

/**
 * Helper to format wei bigint to ETH string for debugging.
 */
export function formatEther(value: bigint): string {
  return ethers.formatEther(value)
}

/**
 * Calculate expected block difference for accumulation tests.
 * This accounts for the actual blocks mined during test execution.
 *
 * @param startBlock - Starting block number
 * @param endBlock - Ending block number
 * @returns Number of blocks for accumulation calculation
 */
export function calculateBlockDifference(startBlock: number, endBlock: number): bigint {
  return BigInt(Math.max(0, endBlock - startBlock))
}

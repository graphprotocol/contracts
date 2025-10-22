/**
 * Performance optimization helpers for test files
 * Focus on reducing code duplication and improving readability
 */

import { expect } from 'chai'
import hre from 'hardhat'
const { ethers } = hre

// Common test constants to avoid magic numbers
const TEST_CONSTANTS = {
  // Common allocation percentages (in PPM)
  ALLOCATION_10_PERCENT: 100_000,
  ALLOCATION_20_PERCENT: 200_000,
  ALLOCATION_30_PERCENT: 300_000,
  ALLOCATION_40_PERCENT: 400_000,
  ALLOCATION_50_PERCENT: 500_000,
  ALLOCATION_60_PERCENT: 600_000,
  ALLOCATION_100_PERCENT: 1_000_000,

  // Common amounts
  AMOUNT_100_TOKENS: '100',
  AMOUNT_1000_TOKENS: '1000',
  AMOUNT_10000_TOKENS: '10000',

  // Time constants
  ONE_DAY: 24 * 60 * 60,
  ONE_WEEK: 7 * 24 * 60 * 60,
  TWO_WEEKS: 14 * 24 * 60 * 60,

  // Common interface IDs (to avoid recalculation)
  ERC165_INTERFACE_ID: '0x01ffc9a7',
  INVALID_INTERFACE_ID: '0x12345678',
}

/**
 * Helper to create consistent ethers amounts
 */
export function parseEther(amount: string): bigint {
  return ethers.parseEther(amount)
}

/**
 * Helper to expect a transaction to revert with a specific custom error
 */
export async function expectCustomError(txPromise: Promise<any>, contract: any, errorName: string): Promise<void> {
  await expect(txPromise).to.be.revertedWithCustomError(contract, errorName)
}

/**
 * Helper to mine blocks for time-sensitive tests
 */
export async function mineBlocks(count: number): Promise<void> {
  for (let i = 0; i < count; i++) {
    await ethers.provider.send('evm_mine', [])
  }
}

export { TEST_CONSTANTS }

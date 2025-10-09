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
 * Helper to test that a value equals another with a descriptive message
 */
export function expectEqual(actual: any, expected: any, message: string = ''): void {
  expect(actual, message).to.equal(expected)
}

/**
 * Helper to mine blocks for time-sensitive tests
 */
export async function mineBlocks(count: number): Promise<void> {
  for (let i = 0; i < count; i++) {
    await ethers.provider.send('evm_mine', [])
  }
}

/**
 * Helper for consistent error messages in tests
 */
const ERROR_MESSAGES = {
  ACCESS_CONTROL: 'AccessControlUnauthorizedAccount',
  INVALID_INITIALIZATION: 'InvalidInitialization',
  ENFORCED_PAUSE: 'EnforcedPause',
  TARGET_ZERO_ADDRESS: 'TargetAddressCannotBeZero',
  GOVERNOR_ZERO_ADDRESS: 'GovernorCannotBeZeroAddress',
  GRAPHTOKEN_ZERO_ADDRESS: 'GraphTokenCannotBeZeroAddress',
  INSUFFICIENT_ALLOCATION: 'InsufficientAllocationAvailable',
  TARGET_NOT_SUPPORTED: 'TargetDoesNotSupportIIssuanceTarget',
  TO_BLOCK_OUT_OF_RANGE: 'ToBlockOutOfRange',
}

/**
 * Helper for common validation test patterns
 */
export async function testValidationErrors(
  validationTests: Array<{ tx: Promise<any>; contract: any; error: string }>,
): Promise<void> {
  for (const test of validationTests) {
    await expectCustomError(test.tx, test.contract, test.error)
  }
}

/**
 * Helper for testing interface support
 */
export async function testInterfaceSupport(
  contract: any,
  supportedInterfaces: string[],
  unsupportedInterface: string = TEST_CONSTANTS.INVALID_INTERFACE_ID,
): Promise<void> {
  // Test supported interfaces
  for (const interfaceId of supportedInterfaces) {
    expect(await contract.supportsInterface(interfaceId)).to.be.true
  }

  // Test unsupported interface
  expect(await contract.supportsInterface(unsupportedInterface)).to.be.false
}

/**
 * Helper for proportional distribution checks
 */
export function expectProportionalDistribution(
  amounts: bigint[],
  expectedRatios: number[],
  tolerance: bigint = 50n,
): void {
  const precision = 1000n
  for (let i = 1; i < amounts.length; i++) {
    const ratio = (amounts[0] * precision) / amounts[i]
    const expectedRatio = BigInt(Math.round((expectedRatios[0] / expectedRatios[i]) * Number(precision)))
    expect(ratio).to.be.closeTo(expectedRatio, tolerance)
  }
}

export { ERROR_MESSAGES, TEST_CONSTANTS }

import hre from 'hardhat'

/**
 * Utility functions for detecting and handling coverage test execution
 */

/**
 * Checks if tests are currently running under solidity-coverage instrumentation
 * @returns true if running under coverage, false otherwise
 */
export function isRunningUnderCoverage(): boolean {
  return hre.__SOLIDITY_COVERAGE_RUNNING === true
}

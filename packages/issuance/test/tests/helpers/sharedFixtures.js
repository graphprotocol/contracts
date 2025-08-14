/**
 * Shared fixtures and setup utilities for all test files
 * Reduces duplication of deployment and state management logic
 */

const { ethers } = require('hardhat')
const { getTestAccounts, deployTestGraphToken, deployServiceQualityOracle } = require('./fixtures')
// Shared test constants
const SHARED_CONSTANTS = {
  PPM: 1_000_000,

  // Pre-calculated role constants to avoid repeated async calls
  GOVERNOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes('GOVERNOR_ROLE')),
  OPERATOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes('OPERATOR_ROLE')),
  PAUSE_ROLE: ethers.keccak256(ethers.toUtf8Bytes('PAUSE_ROLE')),
  ORACLE_ROLE: ethers.keccak256(ethers.toUtf8Bytes('ORACLE_ROLE')),
}

// Interface IDs
const INTERFACE_IDS = {
  IERC165: '0x01ffc9a7',
}

/**
 * Shared contract deployment and setup
 */
async function deploySharedContracts() {
  const accounts = await getTestAccounts()

  // Deploy base contracts
  const graphToken = await deployTestGraphToken()
  const graphTokenAddress = await graphToken.getAddress()

  const serviceQualityOracle = await deployServiceQualityOracle(graphTokenAddress, accounts.governor)

  // Cache addresses
  const addresses = {
    graphToken: graphTokenAddress,
    serviceQualityOracle: await serviceQualityOracle.getAddress(),
  }

  // Create helper
  return {
    accounts,
    contracts: {
      graphToken,
      serviceQualityOracle,
    },
    addresses,
  }
}

/**
 * Reset contract state to initial conditions
 * Optimized to avoid redeployment while ensuring clean state
 */
async function resetContractState(contracts, accounts) {
  const { serviceQualityOracle } = contracts

  // Reset ServiceQualityOracle state
  try {
    if (await serviceQualityOracle.paused()) {
      await serviceQualityOracle.connect(accounts.governor).unpause()
    }

    // Reset quality checking to default (disabled)
    if (await serviceQualityOracle.isQualityCheckingActive()) {
      await serviceQualityOracle.connect(accounts.governor).disableQualityChecking()
    }
  } catch (error) {
    console.warn('ServiceQualityOracle state reset failed:', error instanceof Error ? error.message : String(error))
  }
}

module.exports = {
  deploySharedContracts,
  resetContractState,
  SHARED_CONSTANTS,
  INTERFACE_IDS,
}

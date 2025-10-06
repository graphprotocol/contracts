/**
 * Shared fixtures and setup utilities for all test files
 * Reduces duplication of deployment and state management logic
 */

import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

const { ethers } = require('hardhat')
const { getTestAccounts, deployTestGraphToken, deployRewardsEligibilityOracle } = require('./fixtures')

// Shared test constants
export const SHARED_CONSTANTS = {
  PPM: 1_000_000,

  // Pre-calculated role constants to avoid repeated async calls
  GOVERNOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes('GOVERNOR_ROLE')),
  OPERATOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes('OPERATOR_ROLE')),
  PAUSE_ROLE: ethers.keccak256(ethers.toUtf8Bytes('PAUSE_ROLE')),
  ORACLE_ROLE: ethers.keccak256(ethers.toUtf8Bytes('ORACLE_ROLE')),
} as const

// Interface IDs
export const INTERFACE_IDS = {
  IERC165: '0x01ffc9a7',
} as const

// Types
export interface TestAccounts {
  governor: HardhatEthersSigner
  nonGovernor: HardhatEthersSigner
  operator: HardhatEthersSigner
  user: HardhatEthersSigner
  indexer1: HardhatEthersSigner
  indexer2: HardhatEthersSigner
}

export interface SharedContracts {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  graphToken: any
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  rewardsEligibilityOracle: any
}

export interface SharedAddresses {
  graphToken: string
  rewardsEligibilityOracle: string
}

export interface SharedFixtures {
  accounts: TestAccounts
  contracts: SharedContracts
  addresses: SharedAddresses
}

/**
 * Shared contract deployment and setup
 */
export async function deploySharedContracts(): Promise<SharedFixtures> {
  const accounts = await getTestAccounts()

  // Deploy base contracts
  const graphToken = await deployTestGraphToken()
  const graphTokenAddress = await graphToken.getAddress()

  const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

  // Cache addresses
  const addresses: SharedAddresses = {
    graphToken: graphTokenAddress,
    rewardsEligibilityOracle: await rewardsEligibilityOracle.getAddress(),
  }

  // Create helper
  return {
    accounts,
    contracts: {
      graphToken,
      rewardsEligibilityOracle,
    },
    addresses,
  }
}

/**
 * Reset contract state to initial conditions
 * Optimized to avoid redeployment while ensuring clean state
 */
export async function resetContractState(contracts: SharedContracts, accounts: TestAccounts): Promise<void> {
  const { rewardsEligibilityOracle } = contracts

  // Reset RewardsEligibilityOracle state
  try {
    if (await rewardsEligibilityOracle.paused()) {
      await rewardsEligibilityOracle.connect(accounts.governor).unpause()
    }

    // Reset eligibility validation to default (disabled)
    if (await rewardsEligibilityOracle.getEligibilityValidation()) {
      await rewardsEligibilityOracle.connect(accounts.governor).setEligibilityValidation(false)
    }
  } catch (error) {
    console.warn('RewardsEligibilityOracle state reset failed:', error instanceof Error ? error.message : String(error))
  }
}

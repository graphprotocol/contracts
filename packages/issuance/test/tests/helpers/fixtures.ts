/**
 * Test fixtures and setup utilities
 * Contains deployment functions, shared constants, and test utilities
 */

import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import * as fs from 'fs'

const { ethers, upgrades } = require('hardhat')

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
 * Get standard test accounts
 */
export async function getTestAccounts(): Promise<TestAccounts> {
  const [governor, nonGovernor, operator, user, indexer1, indexer2] = await ethers.getSigners()

  return {
    governor,
    nonGovernor,
    operator,
    user,
    indexer1,
    indexer2,
  }
}

/**
 * Deploy a test GraphToken for testing
 * This uses the real GraphToken contract
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function deployTestGraphToken(): Promise<any> {
  // Get the governor account
  const [governor] = await ethers.getSigners()

  // Load the GraphToken artifact directly from the contracts package
  const graphTokenArtifactPath = require.resolve(
    '@graphprotocol/contracts/artifacts/contracts/token/GraphToken.sol/GraphToken.json',
  )
  const GraphTokenArtifact = JSON.parse(fs.readFileSync(graphTokenArtifactPath, 'utf8'))

  // Create a contract factory using the artifact
  const GraphTokenFactory = new ethers.ContractFactory(GraphTokenArtifact.abi, GraphTokenArtifact.bytecode, governor)

  // Deploy the contract
  const graphToken = await GraphTokenFactory.deploy(ethers.parseEther('1000000000'))
  await graphToken.waitForDeployment()

  return graphToken
}

/**
 * Deploy the RewardsEligibilityOracle contract with proxy using OpenZeppelin's upgrades library
 * @param graphToken The Graph Token contract address
 * @param governor The governor signer
 * @param validityPeriod The validity period in seconds (default: 14 days)
 */
export async function deployRewardsEligibilityOracle(
  graphToken: string,
  governor: HardhatEthersSigner,
  validityPeriod: number = 14 * 24 * 60 * 60, // 14 days in seconds (contract default)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<any> {
  // Deploy implementation and proxy using OpenZeppelin's upgrades library
  const RewardsEligibilityOracleFactory = await ethers.getContractFactory('RewardsEligibilityOracle')

  // Deploy proxy with implementation
  const rewardsEligibilityOracleContract = await upgrades.deployProxy(
    RewardsEligibilityOracleFactory,
    [governor.address],
    {
      constructorArgs: [graphToken],
      initializer: 'initialize',
    },
  )

  // Get the contract instance
  const rewardsEligibilityOracle = rewardsEligibilityOracleContract

  // Set the eligibility period if it's different from the default (14 days)
  if (validityPeriod !== 14 * 24 * 60 * 60) {
    // First grant operator role to governor so they can set the eligibility period
    await rewardsEligibilityOracle.connect(governor).grantRole(SHARED_CONSTANTS.OPERATOR_ROLE, governor.address)
    await rewardsEligibilityOracle.connect(governor).setEligibilityPeriod(validityPeriod)
    // Now revoke the operator role from governor to ensure tests start with clean state
    await rewardsEligibilityOracle.connect(governor).revokeRole(SHARED_CONSTANTS.OPERATOR_ROLE, governor.address)
  }

  return rewardsEligibilityOracle
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

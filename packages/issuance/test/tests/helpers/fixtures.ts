import fs from 'fs'
import hre from 'hardhat'
const { ethers } = hre
const { upgrades } = require('hardhat')
import '@nomicfoundation/hardhat-chai-matchers'

import type { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { GraphTokenHelper } from './graphTokenHelper'

/**
 * Standard test accounts interface
 */
export interface TestAccounts {
  governor: SignerWithAddress
  nonGovernor: SignerWithAddress
  operator: SignerWithAddress
  user: SignerWithAddress
  indexer1: SignerWithAddress
  indexer2: SignerWithAddress
  selfMintingTarget: SignerWithAddress
}

/**
 * Get standard test accounts
 */
async function getTestAccounts(): Promise<TestAccounts> {
  const [governor, nonGovernor, operator, user, indexer1, indexer2, selfMintingTarget] = await ethers.getSigners()

  return {
    governor,
    nonGovernor,
    operator,
    user,
    indexer1,
    indexer2,
    selfMintingTarget,
  }
}

/**
 * Common constants used in tests
 */
const Constants = {
  PPM: 1_000_000, // Parts per million (100%)
  DEFAULT_ISSUANCE_PER_BLOCK: ethers.parseEther('100'), // 100 GRT per block
}

// Shared test constants
export const SHARED_CONSTANTS = {
  PPM: 1_000_000,

  // Pre-calculated role constants to avoid repeated async calls
  GOVERNOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes('GOVERNOR_ROLE')),
  OPERATOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes('OPERATOR_ROLE')),
  PAUSE_ROLE: ethers.keccak256(ethers.toUtf8Bytes('PAUSE_ROLE')),
  ORACLE_ROLE: ethers.keccak256(ethers.toUtf8Bytes('ORACLE_ROLE')),
} as const

/**
 * Deploy a test GraphToken for testing
 * This uses the real GraphToken contract
 * @returns {Promise<Contract>}
 */
async function deployTestGraphToken() {
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
 * Get a GraphTokenHelper for an existing token
 * @param {string} tokenAddress The address of the GraphToken
 * @param {boolean} [isFork=false] Whether this is running on a forked network
 * @returns {Promise<GraphTokenHelper>}
 */
async function getGraphTokenHelper(tokenAddress, isFork = false) {
  // Get the governor account
  const [governor] = await ethers.getSigners()

  // Get the GraphToken at the specified address
  const graphToken = await ethers.getContractAt(isFork ? 'IGraphToken' : 'GraphToken', tokenAddress)

  return new GraphTokenHelper(graphToken, governor)
}

/**
 * Deploy the IssuanceAllocator contract with proxy using OpenZeppelin's upgrades library
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @param {bigint} issuancePerBlock
 * @returns {Promise<IssuanceAllocator>}
 */
async function deployIssuanceAllocator(graphToken, governor, issuancePerBlock) {
  // Deploy implementation and proxy using OpenZeppelin's upgrades library
  const IssuanceAllocatorFactory = await ethers.getContractFactory('IssuanceAllocator')

  // Deploy proxy with implementation
  const issuanceAllocatorContract = await upgrades.deployProxy(IssuanceAllocatorFactory, [governor.address], {
    constructorArgs: [graphToken],
    initializer: 'initialize',
  })

  // Get the contract instance
  const issuanceAllocator = issuanceAllocatorContract

  // Set issuance per block
  await issuanceAllocator.connect(governor).setIssuancePerBlock(issuancePerBlock, false)

  return issuanceAllocator
}

/**
 * Deploy a complete issuance system with production contracts using OpenZeppelin's upgrades library
 * @param {TestAccounts} accounts
 * @param {bigint} [issuancePerBlock=Constants.DEFAULT_ISSUANCE_PER_BLOCK]
 * @returns {Promise<Object>}
 */
async function deployIssuanceSystem(accounts, issuancePerBlock = Constants.DEFAULT_ISSUANCE_PER_BLOCK) {
  const { governor } = accounts

  // Deploy test GraphToken
  const graphToken = await deployTestGraphToken()
  const graphTokenAddress = await graphToken.getAddress()

  // Deploy IssuanceAllocator
  const issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, governor, issuancePerBlock)

  // Add the IssuanceAllocator as a minter on the GraphToken
  const graphTokenHelper = new GraphTokenHelper(graphToken as any, governor)
  await graphTokenHelper.addMinter(await issuanceAllocator.getAddress())

  // Deploy DirectAllocation targets
  const target1 = await deployDirectAllocation(graphTokenAddress, governor)

  const target2 = await deployDirectAllocation(graphTokenAddress, governor)

  // Deploy RewardsEligibilityOracle
  const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, governor)

  return {
    graphToken,
    issuanceAllocator,
    target1,
    target2,
    rewardsEligibilityOracle,
    // For backward compatibility, use the same rewardsEligibilityOracle instance
    expiringRewardsEligibilityOracle: rewardsEligibilityOracle,
  }
}

/**
 * Upgrade a contract using OpenZeppelin's upgrades library
 * This is a generic function that can be used to upgrade any contract
 * @param {string} contractAddress
 * @param {string} contractName
 * @param {any[]} [constructorArgs=[]]
 * @returns {Promise<any>}
 */
async function upgradeContract(contractAddress, contractName, constructorArgs = []) {
  // Get the contract factory
  const ContractFactory = await ethers.getContractFactory(contractName)

  // Upgrade the contract
  const upgradedContractInstance = await upgrades.upgradeProxy(contractAddress, ContractFactory, {
    constructorArgs,
  })

  // Return the upgraded contract instance
  return upgradedContractInstance
}

/**
 * Deploy the DirectAllocation contract with proxy using OpenZeppelin's upgrades library
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @returns {Promise<DirectAllocation>}
 */
async function deployDirectAllocation(graphToken, governor) {
  // Deploy implementation and proxy using OpenZeppelin's upgrades library
  const DirectAllocationFactory = await ethers.getContractFactory('DirectAllocation')

  // Deploy proxy with implementation
  const directAllocationContract = await upgrades.deployProxy(DirectAllocationFactory, [governor.address], {
    constructorArgs: [graphToken],
    initializer: 'initialize',
  })

  // Return the contract instance
  return directAllocationContract
}

/**
 * Deploy the RewardsEligibilityOracle contract with proxy using OpenZeppelin's upgrades library
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @param {number} [validityPeriod=14 * 24 * 60 * 60] The validity period in seconds (default: 14 days)
 * @returns {Promise<RewardsEligibilityOracle>}
 */
async function deployRewardsEligibilityOracle(
  graphToken,
  governor,
  validityPeriod = 14 * 24 * 60 * 60, // 14 days in seconds
) {
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
async function deploySharedContracts() {
  const accounts = await getTestAccounts()

  // Deploy base contracts
  const graphToken = await deployTestGraphToken()
  const graphTokenAddress = await graphToken.getAddress()

  const issuanceAllocator = await deployIssuanceAllocator(
    graphTokenAddress,
    accounts.governor,
    Constants.DEFAULT_ISSUANCE_PER_BLOCK,
  )

  const directAllocation = await deployDirectAllocation(graphTokenAddress, accounts.governor)
  const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

  // Cache addresses
  const addresses = {
    graphToken: graphTokenAddress,
    issuanceAllocator: await issuanceAllocator.getAddress(),
    directAllocation: await directAllocation.getAddress(),
    rewardsEligibilityOracle: await rewardsEligibilityOracle.getAddress(),
  }

  // Create helper
  const graphTokenHelper = new GraphTokenHelper(graphToken as any, accounts.governor)

  return {
    accounts,
    contracts: {
      graphToken,
      issuanceAllocator,
      directAllocation,
      rewardsEligibilityOracle,
    },
    addresses,
    graphTokenHelper,
  }
}

/**
 * Reset contract state to initial conditions
 * Optimized to avoid redeployment while ensuring clean state
 */
async function resetContractState(contracts: any, accounts: any) {
  const { rewardsEligibilityOracle, directAllocation, issuanceAllocator } = contracts

  // Reset RewardsEligibilityOracle state
  try {
    if (await rewardsEligibilityOracle.paused()) {
      await rewardsEligibilityOracle.connect(accounts.governor).unpause()
    }
  } catch {
    // Ignore errors during reset
  }

  // Reset DirectAllocation state
  try {
    if (await directAllocation.paused()) {
      await directAllocation.connect(accounts.governor).unpause()
    }
  } catch {
    // Ignore errors during reset
  }

  // Reset IssuanceAllocator state
  try {
    if (await issuanceAllocator.paused()) {
      await issuanceAllocator.connect(accounts.governor).unpause()
    }
  } catch {
    // Ignore errors during reset
  }
}

// Export all functions and constants
export {
  Constants,
  deployDirectAllocation,
  deployIssuanceAllocator,
  deployIssuanceSystem,
  deployRewardsEligibilityOracle,
  deploySharedContracts,
  deployTestGraphToken,
  getGraphTokenHelper,
  getTestAccounts,
  resetContractState,
  upgradeContract,
}

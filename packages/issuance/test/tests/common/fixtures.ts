/**
 * Common test fixtures shared by all test domains
 * Contains only truly shared functionality used by both allocate and eligibility tests
 */

import '@nomicfoundation/hardhat-chai-matchers'

import fs from 'fs'
import hre from 'hardhat'

const { ethers } = hre
const { upgrades } = require('hardhat')

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
export async function getTestAccounts(): Promise<TestAccounts> {
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
export const Constants = {
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
export async function deployTestGraphToken() {
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
export async function getGraphTokenHelper(tokenAddress, isFork = false) {
  // Get the governor account
  const [governor] = await ethers.getSigners()

  // Get the GraphToken at the specified address
  const graphToken = await ethers.getContractAt(isFork ? 'IGraphToken' : 'GraphToken', tokenAddress)

  return new GraphTokenHelper(graphToken, governor)
}

/**
 * Upgrade a contract using OpenZeppelin's upgrades library
 * This is a generic function that can be used to upgrade any contract
 * @param {string} contractAddress
 * @param {string} contractName
 * @param {any[]} [constructorArgs=[]]
 * @returns {Promise<any>}
 */
export async function upgradeContract(contractAddress, contractName, constructorArgs = []) {
  // Get the contract factory
  const ContractFactory = await ethers.getContractFactory(contractName)

  // Upgrade the contract
  const upgradedContractInstance = await upgrades.upgradeProxy(contractAddress, ContractFactory, {
    constructorArgs,
  })

  // Return the upgraded contract instance
  return upgradedContractInstance
}

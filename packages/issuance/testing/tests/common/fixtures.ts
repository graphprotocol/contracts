/**
 * Common test fixtures shared by all test domains
 * Contains only truly shared functionality used by both allocate and eligibility tests
 */

import '@nomicfoundation/hardhat-ethers-chai-matchers'

import { ethers as ethersLib } from 'ethers'
import fs from 'fs'
import { createRequire } from 'module'

// Create require for ESM compatibility (to resolve package paths)
const require = createRequire(import.meta.url)

import { getEthers, getSigners, type HardhatEthers, type HardhatEthersSigner } from './ethersHelper'
import { GraphTokenHelper } from './graphTokenHelper'

// Re-export from ethersHelper for convenience
export { getEthers, getSigners, type HardhatEthers, type HardhatEthersSigner }

/**
 * Standard test accounts interface
 */
export interface TestAccounts {
  governor: HardhatEthersSigner
  nonGovernor: HardhatEthersSigner
  operator: HardhatEthersSigner
  user: HardhatEthersSigner
  indexer1: HardhatEthersSigner
  indexer2: HardhatEthersSigner
  selfMintingTarget: HardhatEthersSigner
}

/**
 * Get standard test accounts
 */
export async function getTestAccounts(): Promise<TestAccounts> {
  const signers = await getSigners()
  const [governor, nonGovernor, operator, user, indexer1, indexer2, selfMintingTarget] = signers

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
  DEFAULT_ISSUANCE_PER_BLOCK: ethersLib.parseEther('100'), // 100 GRT per block
}

// Shared test constants
export const SHARED_CONSTANTS = {
  PPM: 1_000_000,

  // Pre-calculated role constants to avoid repeated async calls
  GOVERNOR_ROLE: ethersLib.keccak256(ethersLib.toUtf8Bytes('GOVERNOR_ROLE')),
  OPERATOR_ROLE: ethersLib.keccak256(ethersLib.toUtf8Bytes('OPERATOR_ROLE')),
  PAUSE_ROLE: ethersLib.keccak256(ethersLib.toUtf8Bytes('PAUSE_ROLE')),
  ORACLE_ROLE: ethersLib.keccak256(ethersLib.toUtf8Bytes('ORACLE_ROLE')),
} as const

/**
 * Deploy a test GraphToken for testing
 * This uses the real GraphToken contract
 * @returns {Promise<Contract>}
 */
export async function deployTestGraphToken() {
  const ethers = await getEthers()
  // Get the governor account
  const [governor] = await ethers.getSigners()

  // Load the GraphToken artifact directly from the contracts package
  const graphTokenArtifactPath =
    require.resolve('@graphprotocol/contracts/artifacts/contracts/token/GraphToken.sol/GraphToken.json')
  const GraphTokenArtifact = JSON.parse(fs.readFileSync(graphTokenArtifactPath, 'utf8'))

  // Create a contract factory using the artifact
  const GraphTokenFactory = new ethers.ContractFactory(GraphTokenArtifact.abi, GraphTokenArtifact.bytecode, governor)

  // Deploy the contract
  const graphToken = await GraphTokenFactory.deploy(ethersLib.parseEther('1000000000'))
  await graphToken.waitForDeployment()

  return graphToken
}

/**
 * Get a GraphTokenHelper for an existing token
 * @param {string} tokenAddress The address of the GraphToken
 * @param {boolean} [isFork=false] Whether this is running on a forked network
 * @returns {Promise<GraphTokenHelper>}
 */
export async function getGraphTokenHelper(tokenAddress: string, isFork = false) {
  const ethers = await getEthers()
  // Get the governor account
  const [governor] = await ethers.getSigners()

  // Get the GraphToken at the specified address
  const graphToken = await ethers.getContractAt(isFork ? 'IGraphToken' : 'GraphToken', tokenAddress)

  return new GraphTokenHelper(graphToken, governor)
}

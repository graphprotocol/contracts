import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import * as fs from 'fs'

const { ethers, upgrades } = require('hardhat')
const { SHARED_CONSTANTS } = require('./sharedFixtures')
const { OPERATOR_ROLE } = SHARED_CONSTANTS

// Types
export interface TestAccounts {
  governor: HardhatEthersSigner
  nonGovernor: HardhatEthersSigner
  operator: HardhatEthersSigner
  user: HardhatEthersSigner
  indexer1: HardhatEthersSigner
  indexer2: HardhatEthersSigner
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
 * @param validityPeriod The validity period in seconds (default: 7 days)
 */
export async function deployRewardsEligibilityOracle(
  graphToken: string,
  governor: HardhatEthersSigner,
  validityPeriod: number = 7 * 24 * 60 * 60, // 7 days in seconds
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

  // Set the validity period if it's different from the default
  if (validityPeriod !== 7 * 24 * 60 * 60) {
    // First grant operator role to governor so they can set the validity period
    await rewardsEligibilityOracle.connect(governor).grantOperatorRole(governor.address)
    await rewardsEligibilityOracle.connect(governor).setValidityPeriod(validityPeriod)
    // Now revoke the operator role from governor to ensure tests start with clean state
    await rewardsEligibilityOracle.connect(governor).revokeRole(OPERATOR_ROLE, governor.address)
  }

  return rewardsEligibilityOracle
}

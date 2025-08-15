import * as fs from 'fs'
import { ethers, upgrades } from 'hardhat'

/**
 * Standard test accounts
 */
// TestAccounts interface converted to JSDoc for CommonJS
/**
 * @typedef {Object} TestAccounts
 * @property {SignerWithAddress} governor
 * @property {SignerWithAddress} nonGovernor
 * @property {SignerWithAddress} operator
 * @property {SignerWithAddress} user
 * @property {SignerWithAddress} indexer1
 * @property {SignerWithAddress} indexer2
 */

/**
 * Get standard test accounts
 * @returns {Promise<TestAccounts>}
 */
async function getTestAccounts() {
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
 * Deploy the ServiceQualityOracle contract with proxy using OpenZeppelin's upgrades library
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @param {number} [validityPeriod=7 * 24 * 60 * 60] The validity period in seconds (default: 7 days)
 * @returns {Promise<ServiceQualityOracle>}
 */
async function deployServiceQualityOracle(
  graphToken,
  governor,
  validityPeriod = 7 * 24 * 60 * 60, // 7 days in seconds
) {
  // Deploy implementation and proxy using OpenZeppelin's upgrades library
  const ServiceQualityOracleFactory = await ethers.getContractFactory('ServiceQualityOracle')

  // Deploy proxy with implementation
  const serviceQualityOracleContract = await upgrades.deployProxy(ServiceQualityOracleFactory, [governor.address], {
    constructorArgs: [graphToken],
    initializer: 'initialize',
  })

  // Get the contract instance
  const serviceQualityOracle = serviceQualityOracleContract

  // Set the validity period if it's different from the default
  if (validityPeriod !== 7 * 24 * 60 * 60) {
    // First grant operator role to governor so they can set the validity period
    await serviceQualityOracle.connect(governor).grantOperatorRole(governor.address)
    await serviceQualityOracle.connect(governor).setValidityPeriod(validityPeriod)
    // Now revoke the operator role from governor to ensure tests start with clean state
    await serviceQualityOracle.connect(governor).revokeOperatorRole(governor.address)
  }

  return serviceQualityOracle
}

// Export all functions and constants
module.exports = {
  getTestAccounts,
  deployTestGraphToken,
  deployServiceQualityOracle,
}

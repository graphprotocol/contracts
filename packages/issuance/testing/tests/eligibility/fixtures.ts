/**
 * Eligibility-specific test fixtures
 * Deployment and setup functions for eligibility contracts
 */

import fs from 'fs'
import { createRequire } from 'module'

import { getEthers, type HardhatEthersSigner } from '../common/ethersHelper'
import { SHARED_CONSTANTS } from '../common/fixtures'

// Create require for ESM compatibility (to resolve package paths)
const require = createRequire(import.meta.url)

/**
 * Deploy a contract as upgradeable proxy (manual implementation without OZ upgrades plugin)
 * Uses TransparentUpgradeableProxy pattern
 */
async function deployAsProxy(
  contractName: string,
  constructorArgs: unknown[],
  initializerArgs: unknown[],
  admin: HardhatEthersSigner,
) {
  const ethers = await getEthers()

  // Deploy implementation
  const Factory = await ethers.getContractFactory(contractName)
  const implementation = await Factory.deploy(...constructorArgs)
  await implementation.waitForDeployment()

  // Encode initializer call
  const initData = Factory.interface.encodeFunctionData('initialize', initializerArgs)

  // Load TransparentUpgradeableProxy artifact from @openzeppelin/contracts
  const proxyArtifactPath = require.resolve('@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json')
  const ProxyArtifact = JSON.parse(fs.readFileSync(proxyArtifactPath, 'utf8'))

  // Create proxy factory from artifact
  const ProxyFactory = new ethers.ContractFactory(ProxyArtifact.abi, ProxyArtifact.bytecode, admin)
  const proxy = await ProxyFactory.deploy(await implementation.getAddress(), admin.address, initData)
  await proxy.waitForDeployment()

  // Return contract instance attached to proxy address
  return Factory.attach(await proxy.getAddress())
}

/**
 * Deploy the RewardsEligibilityOracle contract with proxy
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @param {number} [validityPeriod=14 * 24 * 60 * 60] The validity period in seconds (default: 14 days)
 * @returns {Promise<any>}
 */
export async function deployRewardsEligibilityOracle(
  graphToken: string,
  governor: HardhatEthersSigner,
  validityPeriod = 14 * 24 * 60 * 60, // 14 days in seconds
) {
  // Deploy with proxy
  const rewardsEligibilityOracle = await deployAsProxy(
    'RewardsEligibilityOracle',
    [graphToken], // constructor args
    [governor.address], // initialize args
    governor,
  )

  // Set the eligibility period if it's different from the default (14 days)
  if (validityPeriod !== 14 * 24 * 60 * 60) {
    // First grant operator role to governor so they can set the eligibility period
    await (rewardsEligibilityOracle as any)
      .connect(governor)
      .grantRole(SHARED_CONSTANTS.OPERATOR_ROLE, governor.address)
    await (rewardsEligibilityOracle as any).connect(governor).setEligibilityPeriod(validityPeriod)
    // Now revoke the operator role from governor to ensure tests start with clean state
    await (rewardsEligibilityOracle as any)
      .connect(governor)
      .revokeRole(SHARED_CONSTANTS.OPERATOR_ROLE, governor.address)
  }

  return rewardsEligibilityOracle
}

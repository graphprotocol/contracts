/**
 * Eligibility-specific test fixtures
 * Deployment and setup functions for eligibility contracts
 */

import hre from 'hardhat'

const { ethers } = hre
const { upgrades } = require('hardhat')

import { SHARED_CONSTANTS } from '../common/fixtures'

/**
 * Deploy the RewardsEligibilityOracle contract with proxy using OpenZeppelin's upgrades library
 * @param {string} graphToken
 * @param {HardhatEthersSigner} governor
 * @param {number} [validityPeriod=14 * 24 * 60 * 60] The validity period in seconds (default: 14 days)
 * @returns {Promise<RewardsEligibilityOracle>}
 */
export async function deployRewardsEligibilityOracle(
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

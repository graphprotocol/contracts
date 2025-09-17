/* eslint-disable @typescript-eslint/no-explicit-any */
import { expect } from 'chai'
import { ethers } from 'hardhat'

import { shouldSupportERC165Interface } from '../../utils/testPatterns'
import { deployRewardsEligibilityOracle, deployTestGraphToken, getTestAccounts } from '../helpers/fixtures'
// Import generated interface IDs
import interfaceIds from '../helpers/interfaceIds'

/**
 * Consolidated ERC-165 Interface Compliance Tests
 * Tests interface support across all contracts to reduce duplication
 */
describe('ERC-165 Interface Compliance', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy all contracts for interface testing
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

    contracts = {
      rewardsEligibilityOracle,
    }
  })

  describe(
    'RewardsEligibilityOracle Interface Compliance',
    shouldSupportERC165Interface(
      () => contracts.rewardsEligibilityOracle,
      interfaceIds.IRewardsEligibilityOracle,
      'IRewardsEligibilityOracle',
    ),
  )

  describe('Interface ID Consistency', () => {
    it('should have consistent interface IDs with Solidity calculations', async () => {
      const InterfaceIdExtractorFactory = await ethers.getContractFactory('InterfaceIdExtractor')
      const extractor = await InterfaceIdExtractorFactory.deploy()

      expect(await extractor.getIRewardsEligibilityOracleId()).to.equal(interfaceIds.IRewardsEligibilityOracle)
    })

    it('should have valid interface IDs (not zero)', () => {
      expect(interfaceIds.IRewardsEligibilityOracle).to.not.equal('0x00000000')
    })
  })
})

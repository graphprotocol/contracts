import { expect } from 'chai'
const { ethers } = require('hardhat')

const { shouldSupportERC165Interface } = require('../../utils/testPatterns')
import {
  deployDirectAllocation,
  deployIssuanceAllocator,
  deployRewardsEligibilityOracle,
  deployTestGraphToken,
  getTestAccounts,
} from '../helpers/fixtures'
// Import generated interface IDs
import { IIssuanceAllocator, IIssuanceTarget, IRewardsEligibilityOracle } from '../helpers/interfaceIds'

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

    const issuanceAllocator = await deployIssuanceAllocator(
      graphTokenAddress,
      accounts.governor,
      ethers.parseEther('100'),
    )

    const directAllocation = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

    contracts = {
      issuanceAllocator,
      directAllocation,
      rewardsEligibilityOracle,
    }
  })

  describe(
    'IssuanceAllocator Interface Compliance',
    shouldSupportERC165Interface(() => contracts.issuanceAllocator, IIssuanceAllocator, 'IIssuanceAllocator'),
  )

  describe(
    'DirectAllocation Interface Compliance',
    shouldSupportERC165Interface(() => contracts.directAllocation, IIssuanceTarget, 'IIssuanceTarget'),
  )

  describe(
    'RewardsEligibilityOracle Interface Compliance',
    shouldSupportERC165Interface(
      () => contracts.rewardsEligibilityOracle,
      IRewardsEligibilityOracle,
      'IRewardsEligibilityOracle',
    ),
  )

  describe('Interface ID Consistency', () => {
    it('should have consistent interface IDs with Solidity calculations', async () => {
      const InterfaceIdExtractorFactory = await ethers.getContractFactory('InterfaceIdExtractor')
      const extractor = await InterfaceIdExtractorFactory.deploy()

      // Verify each interface ID matches what Solidity calculates
      expect(await extractor.getIIssuanceAllocatorId()).to.equal(IIssuanceAllocator)
      expect(await extractor.getIRewardsEligibilityOracleId()).to.equal(IRewardsEligibilityOracle)
      expect(await extractor.getIIssuanceTargetId()).to.equal(IIssuanceTarget)
    })

    it('should have valid interface IDs (not zero)', () => {
      expect(IIssuanceAllocator).to.not.equal('0x00000000')
      expect(IRewardsEligibilityOracle).to.not.equal('0x00000000')
      expect(IIssuanceTarget).to.not.equal('0x00000000')
    })

    it('should have unique interface IDs', () => {
      const ids = [IIssuanceAllocator, IRewardsEligibilityOracle, IIssuanceTarget]

      const uniqueIds = new Set(ids)
      expect(uniqueIds.size).to.equal(ids.length, 'All interface IDs should be unique')
    })
  })
})

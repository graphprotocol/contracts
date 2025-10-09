// Import generated interface IDs from the interfaces package
import { IIssuanceAllocator, IIssuanceTarget, IRewardsEligibilityOracle } from '@graphprotocol/interfaces'
import { expect } from 'chai'
import { ethers } from 'hardhat'

import { shouldSupportERC165Interface } from '../../utils/testPatterns'
import {
  deployDirectAllocation,
  deployIssuanceAllocator,
  deployRewardsEligibilityOracle,
  deployTestGraphToken,
  getTestAccounts,
} from '../helpers/fixtures'

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

  describe('Interface ID Validation', () => {
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

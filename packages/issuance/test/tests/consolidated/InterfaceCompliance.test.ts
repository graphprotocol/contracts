// Import generated interface IDs from the interfaces package
import {
  IIssuanceAllocationAdministration,
  IIssuanceAllocationDistribution,
  IIssuanceAllocationStatus,
  IIssuanceTarget,
  IRewardsEligibility,
  IRewardsEligibilityAdministration,
  IRewardsEligibilityReporting,
  IRewardsEligibilityStatus,
} from '@graphprotocol/interfaces'
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

  describe('IssuanceAllocator Interface Compliance', () => {
    it('should support IIssuanceAllocationDistribution interface', async () => {
      const allocator = contracts.issuanceAllocator
      const supported = await allocator.supportsInterface(IIssuanceAllocationDistribution)
      expect(supported).to.be.true
    })

    it('should support IIssuanceAllocationAdministration interface', async () => {
      const allocator = contracts.issuanceAllocator
      const supported = await allocator.supportsInterface(IIssuanceAllocationAdministration)
      expect(supported).to.be.true
    })

    it('should support IIssuanceAllocationStatus interface', async () => {
      const allocator = contracts.issuanceAllocator
      const supported = await allocator.supportsInterface(IIssuanceAllocationStatus)
      expect(supported).to.be.true
    })

    it('should support ERC-165 interface', async () => {
      const allocator = contracts.issuanceAllocator
      const supported = await allocator.supportsInterface('0x01ffc9a7')
      expect(supported).to.be.true
    })

    it('should not support random interface', async () => {
      const allocator = contracts.issuanceAllocator
      const supported = await allocator.supportsInterface('0xffffffff')
      expect(supported).to.be.false
    })
  })

  describe(
    'DirectAllocation Interface Compliance',
    shouldSupportERC165Interface(() => contracts.directAllocation, IIssuanceTarget, 'IIssuanceTarget'),
  )

  describe('RewardsEligibilityOracle Interface Compliance', () => {
    it('should support IRewardsEligibility interface', async () => {
      const oracle = contracts.rewardsEligibilityOracle
      const supported = await oracle.supportsInterface(IRewardsEligibility)
      expect(supported).to.be.true
    })

    it('should support IRewardsEligibilityAdministration interface', async () => {
      const oracle = contracts.rewardsEligibilityOracle
      const supported = await oracle.supportsInterface(IRewardsEligibilityAdministration)
      expect(supported).to.be.true
    })

    it('should support IRewardsEligibilityReporting interface', async () => {
      const oracle = contracts.rewardsEligibilityOracle
      const supported = await oracle.supportsInterface(IRewardsEligibilityReporting)
      expect(supported).to.be.true
    })

    it('should support IRewardsEligibilityStatus interface', async () => {
      const oracle = contracts.rewardsEligibilityOracle
      const supported = await oracle.supportsInterface(IRewardsEligibilityStatus)
      expect(supported).to.be.true
    })

    it('should support ERC-165 interface', async () => {
      const oracle = contracts.rewardsEligibilityOracle
      const supported = await oracle.supportsInterface('0x01ffc9a7')
      expect(supported).to.be.true
    })

    it('should not support random interface', async () => {
      const oracle = contracts.rewardsEligibilityOracle
      const supported = await oracle.supportsInterface('0xffffffff')
      expect(supported).to.be.false
    })
  })

  describe('Interface ID Validation', () => {
    it('should have valid interface IDs (not zero)', () => {
      expect(IIssuanceAllocationDistribution).to.not.equal('0x00000000')
      expect(IIssuanceAllocationAdministration).to.not.equal('0x00000000')
      expect(IIssuanceAllocationStatus).to.not.equal('0x00000000')
      expect(IRewardsEligibility).to.not.equal('0x00000000')
      expect(IRewardsEligibilityAdministration).to.not.equal('0x00000000')
      expect(IRewardsEligibilityReporting).to.not.equal('0x00000000')
      expect(IRewardsEligibilityStatus).to.not.equal('0x00000000')
      expect(IIssuanceTarget).to.not.equal('0x00000000')
    })

    it('should have unique interface IDs', () => {
      const ids = [
        IIssuanceAllocationDistribution,
        IIssuanceAllocationAdministration,
        IIssuanceAllocationStatus,
        IRewardsEligibility,
        IRewardsEligibilityAdministration,
        IRewardsEligibilityReporting,
        IRewardsEligibilityStatus,
        IIssuanceTarget,
      ]

      const uniqueIds = new Set(ids)
      expect(uniqueIds.size).to.equal(ids.length, 'All interface IDs should be unique')
    })
  })
})

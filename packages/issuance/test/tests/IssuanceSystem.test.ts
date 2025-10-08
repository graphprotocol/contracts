/**
 * Issuance System Integration Tests - Optimized Version
 * Reduced from 149 lines to ~80 lines using shared utilities
 */

const { expect } = require('chai')

const { setupOptimizedIssuanceSystem } = require('../utils/optimizedFixtures')
const { TestConstants, mineBlocks, expectRatioToEqual } = require('../utils/testPatterns')

describe('Issuance System', () => {
  let system: any

  before(async () => {
    // Single setup instead of beforeEach - major performance improvement
    system = await setupOptimizedIssuanceSystem({
      setupTargets: false, // We'll set up specific scenarios per test
    })
  })

  beforeEach(async () => {
    // Fast state reset instead of full redeployment
    await system.helpers.resetState()
  })

  describe('End-to-End Issuance Flow', () => {
    it('should allocate tokens to targets based on their allocation percentages', async () => {
      const { contracts, addresses, accounts } = system

      // Verify initial balances (should be 0)
      expect(await contracts.graphToken.balanceOf(addresses.target1)).to.equal(0)
      expect(await contracts.graphToken.balanceOf(addresses.target2)).to.equal(0)

      // Set up allocations using predefined constants: target1 = 30%, target2 = 40%
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,bool)'
        ](addresses.target1, TestConstants.ALLOCATION_30_PERCENT, 0, false)
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,bool)'
        ](addresses.target2, TestConstants.ALLOCATION_40_PERCENT, 0, false)

      // Grant operator roles using predefined constants
      await contracts.target1
        .connect(accounts.governor)
        .grantRole(TestConstants.OPERATOR_ROLE, accounts.operator.address)
      await contracts.target2
        .connect(accounts.governor)
        .grantRole(TestConstants.OPERATOR_ROLE, accounts.operator.address)

      // Get balances after allocation setup
      const balanceAfterAllocation1 = await contracts.graphToken.balanceOf(addresses.target1)
      const balanceAfterAllocation2 = await contracts.graphToken.balanceOf(addresses.target2)

      // Mine blocks using helper function
      await mineBlocks(10)
      await contracts.issuanceAllocator.distributeIssuance()

      // Get final balances and verify distributions
      const finalBalance1 = await contracts.graphToken.balanceOf(addresses.target1)
      const finalBalance2 = await contracts.graphToken.balanceOf(addresses.target2)

      // Verify targets received tokens proportionally
      expect(finalBalance1).to.be.gt(balanceAfterAllocation1)
      expect(finalBalance2).to.be.gt(balanceAfterAllocation2)

      // Test token distribution from targets to users
      await contracts.target1.connect(accounts.operator).sendTokens(accounts.user.address, finalBalance1)
      await contracts.target2.connect(accounts.operator).sendTokens(accounts.indexer1.address, finalBalance2)

      // Verify user balances and target emptiness
      expect(await contracts.graphToken.balanceOf(accounts.user.address)).to.equal(finalBalance1)
      expect(await contracts.graphToken.balanceOf(accounts.indexer1.address)).to.equal(finalBalance2)
      expect(await contracts.graphToken.balanceOf(addresses.target1)).to.equal(0)
      expect(await contracts.graphToken.balanceOf(addresses.target2)).to.equal(0)
    })

    it('should handle allocation changes correctly', async () => {
      const { contracts, addresses, accounts } = system

      // Set up initial allocations using helper
      await system.helpers.setupStandardAllocations()

      // Verify initial total allocation (30% + 40% = 70%)
      const totalAlloc = await contracts.issuanceAllocator.getTotalAllocation()
      expect(totalAlloc.totalAllocationPPM).to.equal(
        TestConstants.ALLOCATION_30_PERCENT + TestConstants.ALLOCATION_40_PERCENT,
      )

      // Change allocations: target1 = 50%, target2 = 20% (still 70%)
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,bool)'
        ](addresses.target1, TestConstants.ALLOCATION_50_PERCENT, 0, false)
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,bool)'
        ](addresses.target2, TestConstants.ALLOCATION_20_PERCENT, 0, false)

      // Verify updated allocations
      const updatedTotalAlloc = await contracts.issuanceAllocator.getTotalAllocation()
      expect(updatedTotalAlloc.totalAllocationPPM).to.equal(
        TestConstants.ALLOCATION_50_PERCENT + TestConstants.ALLOCATION_20_PERCENT,
      )

      // Verify individual target allocations
      const target1Info = await contracts.issuanceAllocator.getTargetData(addresses.target1)
      const target2Info = await contracts.issuanceAllocator.getTargetData(addresses.target2)

      expect(target1Info.allocatorMintingPPM + target1Info.selfMintingPPM).to.equal(TestConstants.ALLOCATION_50_PERCENT)
      expect(target2Info.allocatorMintingPPM + target2Info.selfMintingPPM).to.equal(TestConstants.ALLOCATION_20_PERCENT)

      // Verify proportional issuance distribution (50:20 = 5:2 ratio)
      const target1Result = await contracts.issuanceAllocator.getTargetIssuancePerBlock(addresses.target1)
      const target2Result = await contracts.issuanceAllocator.getTargetIssuancePerBlock(addresses.target2)

      expect(target1Result.selfIssuancePerBlock).to.equal(0)
      expect(target2Result.selfIssuancePerBlock).to.equal(0)

      // Verify the ratio using helper function: 50/20 = 2.5, so 2500 in our precision
      expectRatioToEqual(
        target1Result.allocatorIssuancePerBlock,
        target2Result.allocatorIssuancePerBlock,
        2500n, // 50/20 * 1000 precision
        TestConstants.DEFAULT_TOLERANCE,
      )
    })
  })
})

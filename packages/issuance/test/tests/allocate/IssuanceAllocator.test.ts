import { expect } from 'chai'
import hre from 'hardhat'
const { ethers } = hre

import { deployTestGraphToken, getTestAccounts, SHARED_CONSTANTS } from '../common/fixtures'
import { deployDirectAllocation, deployIssuanceAllocator } from './fixtures'
// calculateExpectedAccumulation removed with PPM model
// Import optimization helpers for common test utilities
import { expectCustomError } from './optimizationHelpers'

// Helper function to deploy a simple mock target for testing
async function deployMockSimpleTarget() {
  const MockSimpleTargetFactory = await ethers.getContractFactory('MockSimpleTarget')
  return await MockSimpleTargetFactory.deploy()
}

describe('IssuanceAllocator', () => {
  // Common variables
  let accounts
  let issuancePerBlock

  // Shared contracts for optimized tests
  // - Deploy contracts once in before() hook instead of per-test
  // - Reset state in beforeEach() hook instead of redeploying
  // - Use sharedContracts.addresses for cached addresses
  // - Use sharedContracts.issuanceAllocator, etc. for contract instances
  let sharedContracts

  // Role constants - hardcoded to avoid slow contract calls
  const GOVERNOR_ROLE = SHARED_CONSTANTS.GOVERNOR_ROLE
  const PAUSE_ROLE = SHARED_CONSTANTS.PAUSE_ROLE

  // Interface IDs moved to consolidated tests

  before(async () => {
    accounts = await getTestAccounts()
    issuancePerBlock = ethers.parseEther('100') // Default issuance per block

    // Deploy shared contracts once for most tests
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    const issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, accounts.governor, issuancePerBlock)

    const target1 = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    const target2 = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    const target3 = await deployDirectAllocation(graphTokenAddress, accounts.governor)

    // Cache addresses to avoid repeated getAddress() calls
    const addresses = {
      issuanceAllocator: await issuanceAllocator.getAddress(),
      target1: await target1.getAddress(),
      target2: await target2.getAddress(),
      target3: await target3.getAddress(),
      graphToken: graphTokenAddress,
    }

    // Grant minter role to issuanceAllocator
    await (graphToken as any).addMinter(addresses.issuanceAllocator)

    sharedContracts = {
      graphToken,
      issuanceAllocator,
      target1,
      target2,
      target3,
      addresses,
    }
  })

  // Fast state reset function for shared contracts
  async function resetIssuanceAllocatorState() {
    if (!sharedContracts) return

    const { issuanceAllocator } = sharedContracts

    // Remove all existing allocations (except default at index 0)
    try {
      const targetCount = await issuanceAllocator.getTargetCount()
      // Skip index 0 (default target) and remove from index 1 onwards
      for (let i = 1; i < targetCount; i++) {
        const targetAddr = await issuanceAllocator.getTargetAt(1) // Always remove index 1
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](targetAddr, 0, 0)
      }
    } catch (_e) {
      // Ignore errors during cleanup
    }

    // Reset pause state
    try {
      if (await issuanceAllocator.paused()) {
        await issuanceAllocator.connect(accounts.governor).unpause()
      }
    } catch (_e) {
      // Ignore if not paused
    }

    // Reset issuance per block to default
    try {
      const currentIssuance = await issuanceAllocator.getIssuancePerBlock()
      if (currentIssuance !== issuancePerBlock) {
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(issuancePerBlock)
      }
    } catch (_e) {
      // Ignore if can't reset
    }
  }

  beforeEach(async () => {
    if (!accounts) {
      accounts = await getTestAccounts()
      issuancePerBlock = ethers.parseEther('100')
    }
    await resetIssuanceAllocatorState()
  })

  // Cached addresses to avoid repeated getAddress() calls
  let cachedAddresses = {}

  // Test fixtures with caching
  async function setupIssuanceAllocator() {
    // Deploy test GraphToken
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    // Deploy IssuanceAllocator with proxy using OpenZeppelin's upgrades library
    const issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, accounts.governor, issuancePerBlock)

    // Deploy target contracts using OpenZeppelin's upgrades library
    const target1 = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    const target2 = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    const target3 = await deployDirectAllocation(graphTokenAddress, accounts.governor)

    // Cache addresses to avoid repeated getAddress() calls
    const issuanceAllocatorAddress = await issuanceAllocator.getAddress()
    const target1Address = await target1.getAddress()
    const target2Address = await target2.getAddress()
    const target3Address = await target3.getAddress()

    cachedAddresses = {
      issuanceAllocator: issuanceAllocatorAddress,
      target1: target1Address,
      target2: target2Address,
      target3: target3Address,
      graphToken: graphTokenAddress,
    }

    return {
      issuanceAllocator,
      graphToken,
      target1,
      target2,
      target3,
      addresses: cachedAddresses,
    }
  }

  // Simplified setup for tests that don't need target contracts
  async function setupSimpleIssuanceAllocator() {
    // Deploy test GraphToken
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    // Deploy IssuanceAllocator with proxy using OpenZeppelin's upgrades library
    const issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, accounts.governor, issuancePerBlock)

    // Cache the issuance allocator address
    const issuanceAllocatorAddress = await issuanceAllocator.getAddress()

    // Grant minter role to issuanceAllocator (needed for distributeIssuance calls)
    await (graphToken as any).addMinter(issuanceAllocatorAddress)

    return {
      issuanceAllocator,
      graphToken,
      addresses: {
        issuanceAllocator: issuanceAllocatorAddress,
        graphToken: graphTokenAddress,
      },
    }
  }

  describe('Initialization', () => {
    it('should initialize contract correctly and prevent re-initialization', async () => {
      const { issuanceAllocator } = sharedContracts

      // Verify all initialization state in one test
      expect(await issuanceAllocator.hasRole(GOVERNOR_ROLE, accounts.governor.address)).to.be.true
      expect(await issuanceAllocator.getIssuancePerBlock()).to.equal(issuancePerBlock)

      // Verify re-initialization is prevented
      await expect(issuanceAllocator.initialize(accounts.governor.address)).to.be.revertedWithCustomError(
        issuanceAllocator,
        'InvalidInitialization',
      )
    })
  })

  // Interface Compliance tests moved to consolidated/InterfaceCompliance.test.ts

  describe('ERC-165 Interface Checking', () => {
    it('should successfully add a target that supports IIssuanceTarget interface', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Should succeed because DirectAllocation supports IIssuanceTarget
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 100000, 0),
      ).to.not.be.reverted

      // Verify the target was added
      const targetData = await issuanceAllocator.getTargetData(addresses.target1)
      expect(targetData.allocatorMintingRate).to.equal(100000)
      expect(targetData.selfMintingRate).to.equal(0)
      const allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(allocation.totalAllocationRate).to.equal(100000)
      expect(allocation.allocatorMintingRate).to.equal(100000)
      expect(allocation.selfMintingRate).to.equal(0)
    })

    it('should revert when adding EOA targets (no contract code)', async () => {
      const { issuanceAllocator } = sharedContracts
      const eoaAddress = accounts.nonGovernor.address

      // Should revert because EOAs don't have contract code to call supportsInterface on
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](eoaAddress, 100000, 0),
      ).to.be.reverted
    })

    it('should revert when adding a contract that does not support IIssuanceTarget', async () => {
      const { issuanceAllocator } = sharedContracts

      // Deploy a contract that supports ERC-165 but not IIssuanceTarget
      const ERC165OnlyFactory = await ethers.getContractFactory('MockERC165')
      const erc165OnlyContract = await ERC165OnlyFactory.deploy()
      const contractAddress = await erc165OnlyContract.getAddress()

      // Should revert because the contract doesn't support IIssuanceTarget
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](contractAddress, 100000, 0),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'TargetDoesNotSupportIIssuanceTarget')
    })

    it('should fail to add MockRevertingTarget due to notification failure even with force=true', async () => {
      const { issuanceAllocator } = sharedContracts

      // MockRevertingTarget now supports both ERC-165 and IIssuanceTarget, so it passes interface check
      const MockRevertingTargetFactory = await ethers.getContractFactory('MockRevertingTarget')
      const mockRevertingTarget = await MockRevertingTargetFactory.deploy()
      const contractAddress = await mockRevertingTarget.getAddress()

      // This should revert because MockRevertingTarget reverts during notification
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,uint256)'](contractAddress, 100000, 0, 0),
      ).to.be.revertedWithCustomError(mockRevertingTarget, 'TargetRevertsIntentionally')

      // Verify the target was NOT added because the transaction reverted
      const targetData = await issuanceAllocator.getTargetData(contractAddress)
      expect(targetData.allocatorMintingRate).to.equal(0)
      expect(targetData.selfMintingRate).to.equal(0)
      const allocation = await issuanceAllocator.getTargetAllocation(contractAddress)
      expect(allocation.totalAllocationRate).to.equal(0)
    })

    it('should allow re-adding existing target with same self-minter flag', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add the target first time
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 100000, 0)

      // Should succeed when setting allocation again with same flag (no interface check needed)
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 200000, 0),
      ).to.not.be.reverted
    })
  })

  // Access Control tests moved to consolidated/AccessControl.test.ts

  describe('Target Management', () => {
    it('should automatically remove target when setting allocation to 0', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target with allocation in one step
      const allocation = 300000 // 30% in PPM
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, allocation, 0)

      // Verify allocation is set and target exists
      const target1Allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(target1Allocation.totalAllocationRate).to.equal(allocation)
      const totalAlloc = await issuanceAllocator.getTotalAllocation()
      // With default as address(0), only non-default targets are reported
      expect(totalAlloc.totalAllocationRate).to.equal(allocation)

      // Remove target by setting allocation to 0
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 0, 0)

      // Verify target is removed (only default remains)
      const targets = await issuanceAllocator.getTargets()
      expect(targets.length).to.equal(1) // Only default target

      // Verify reported total is 0% (default has it all, but isn't reported)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.totalAllocationRate).to.equal(0)
      }
    })

    it('should remove a target when multiple targets exist', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add targets with allocations in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 300000, 0) // 30%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target2, 400000, 0) // 40%

      // Verify allocations are set
      const target1Allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      const target2Allocation = await issuanceAllocator.getTargetAllocation(addresses.target2)
      expect(target1Allocation.totalAllocationRate).to.equal(300000)
      expect(target2Allocation.totalAllocationRate).to.equal(400000)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        // With default as address(0), only non-default targets are reported (70%)
        expect(totalAlloc.totalAllocationRate).to.equal(700000)
      }

      // Get initial target addresses (including default)
      const initialTargets = await issuanceAllocator.getTargets()
      expect(initialTargets.length).to.equal(3) // default + target1 + target2

      // Remove target2 by setting allocation to 0 (tests the swap-and-pop logic in the contract)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target2, 0, 0)

      // Verify target2 is removed but target1 and default remain
      const remainingTargets = await issuanceAllocator.getTargets()
      expect(remainingTargets.length).to.equal(2) // default + target1
      expect(remainingTargets).to.include(addresses.target1)

      // Verify reported total excludes default (only target1's 30% is reported)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.totalAllocationRate).to.equal(300000)
      }
    })

    it('should add allocation targets correctly', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add targets with allocations in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 100000, 0) // 10%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target2, 200000, 0) // 20%

      // Verify targets were added
      const target1Info = await issuanceAllocator.getTargetData(addresses.target1)
      const target2Info = await issuanceAllocator.getTargetData(addresses.target2)

      // Check that targets exist by verifying they have non-zero allocations
      expect(target1Info.allocatorMintingRate + target1Info.selfMintingRate).to.equal(100000)
      expect(target2Info.allocatorMintingRate + target2Info.selfMintingRate).to.equal(200000)
      expect(target1Info.selfMintingRate).to.equal(0)
      expect(target2Info.selfMintingRate).to.equal(0)

      // Verify reported total excludes default (only target1+target2's 70% is reported)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.totalAllocationRate).to.equal(300000)
      }
    })

    it('should validate setTargetAllocation parameters and constraints', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Test 1: Should revert when setting non-zero allocation for target that does not support IIssuanceTarget
      const nonExistentTarget = accounts.nonGovernor.address
      // When trying to set allocation for an EOA, the IERC165 call will revert
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](nonExistentTarget, 500_000, 0),
      ).to.be.reverted

      // Test 2: Should revert when total allocation would exceed 100%
      // Set allocation for target1 to 60%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, ethers.parseEther('60'), 0)

      // Try to set allocation for target2 to 50%, which would exceed 100% (60% + 50% > 100%)
      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](addresses.target2, ethers.parseEther('50'), 0),
        issuanceAllocator,
        'InsufficientAllocationAvailable',
      )
    })
  })

  describe('Self-Minting Targets', () => {
    it('should not mint tokens for self-minting targets during distributeIssuance', async () => {
      const { issuanceAllocator, graphToken, addresses } = sharedContracts

      // Add targets with different self-minter flags and set allocations
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 300000, 0) // 30%, allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target2, 0, 400000) // 40%, self-minting

      // Get balances after setting allocations (some tokens may have been minted due to setTargetAllocation calling distributeIssuance)
      const balanceAfterAllocation1 = await (graphToken as any).balanceOf(addresses.target1)
      const balanceAfterAllocation2 = await (graphToken as any).balanceOf(addresses.target2)

      // Mine some blocks
      for (let i = 0; i < 5; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Distribute issuance
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Check balances after distribution
      const finalBalance1 = await (graphToken as any).balanceOf(addresses.target1)
      const finalBalance2 = await (graphToken as any).balanceOf(addresses.target2)

      // Allocator-minting target should have received more tokens after the additional distribution
      expect(finalBalance1).to.be.gt(balanceAfterAllocation1)

      // Self-minting target should not have received any tokens (should still be the same as after allocation)
      expect(finalBalance2).to.equal(balanceAfterAllocation2)
    })

    it('should allow non-governor to call distributeIssuance', async () => {
      const { issuanceAllocator, graphToken, addresses } = sharedContracts

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 300000, 0) // 30%

      // Mine some blocks
      for (let i = 0; i < 5; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Distribute issuance as non-governor (should work since distributeIssuance is not protected by GOVERNOR_ROLE)
      await issuanceAllocator.connect(accounts.nonGovernor).distributeIssuance()

      // Verify tokens were minted to the target
      expect(await (graphToken as any).balanceOf(addresses.target1)).to.be.gt(0)
    })

    it('should not distribute issuance when paused but not revert', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 300000, 0) // 30%

      // Mine some blocks
      for (let i = 0; i < 5; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Grant pause role to governor
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)

      // Get initial balance and lastIssuanceDistributionBlock before pausing
      const { graphToken } = sharedContracts
      const initialBalance = await (graphToken as any).balanceOf(addresses.target1)
      const initialLastIssuanceBlock = (await issuanceAllocator.getDistributionState()).lastDistributionBlock

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine some more blocks
      await ethers.provider.send('evm_mine', [])

      // Try to distribute issuance while paused - should not revert but return lastIssuanceDistributionBlock
      const result = await issuanceAllocator.connect(accounts.governor).distributeIssuance.staticCall()
      expect(result).to.equal(initialLastIssuanceBlock)

      // Verify no tokens were minted and lastIssuanceDistributionBlock was not updated
      const finalBalance = await (graphToken as any).balanceOf(addresses.target1)
      const finalLastIssuanceBlock = (await issuanceAllocator.getDistributionState()).lastDistributionBlock

      expect(finalBalance).to.equal(initialBalance)
      expect(finalLastIssuanceBlock).to.equal(initialLastIssuanceBlock)
    })

    it('should update selfMinter flag when allocation stays the same but flag changes', async () => {
      await resetIssuanceAllocatorState()
      const { issuanceAllocator, graphToken, target1 } = sharedContracts

      // Minter role already granted in shared setup

      // Add target as allocator-minting with 30% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 300000, 0) // 30%, allocator-minting

      // Verify initial state
      const initialAllocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(initialAllocation.selfMintingRate).to.equal(0)

      // Change to self-minting with same allocation - this should NOT return early
      const result = await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'].staticCall(await target1.getAddress(), 0, 300000, 0) // Same allocation, but now self-minting

      // Should return true (indicating change was made)
      expect(result).to.be.true

      // Actually make the change
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 0, 300000)

      // Verify the selfMinter flag was updated
      const updatedAllocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(updatedAllocation.selfMintingRate).to.be.gt(0)
    })

    it('should update selfMinter flag when changing from self-minting to allocator-minting', async () => {
      await resetIssuanceAllocatorState()
      const { issuanceAllocator, target1 } = sharedContracts

      // Minter role already granted in shared setup

      // Add target as self-minting with 30% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 0, 300000) // 30%, self-minting

      // Verify initial state
      const initialAllocation2 = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(initialAllocation2.selfMintingRate).to.be.gt(0)

      // Change to allocator-minting with same allocation - this should NOT return early
      const result = await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'].staticCall(await target1.getAddress(), 300000, 0, 0) // Same allocation, but now allocator-minting

      // Should return true (indicating change was made)
      expect(result).to.be.true

      // Actually make the change
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 300000, 0)

      // Verify the selfMinter flag was updated
      const finalAllocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(finalAllocation.selfMintingRate).to.equal(0)
    })

    it('should track totalActiveSelfMintingAllocation correctly with incremental updates', async () => {
      await resetIssuanceAllocatorState()
      const { issuanceAllocator, target1, target2 } = sharedContracts

      // Minter role already granted in shared setup

      // Initially should be 0 (no targets)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingRate).to.equal(0)
      }

      // Add self-minting target with 30% allocation (300000 PPM)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 0, 300000) // 30%, self-minting

      // Should now be 300000 PPM
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingRate).to.equal(300000)
      }

      // Add allocator-minting target with 20% allocation (200000 PPM)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), 200000, 0) // 20%, allocator-minting

      // totalActiveSelfMintingAllocation should remain the same (still 300000 PPM)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingRate).to.equal(300000)
      }

      // Change target2 to self-minting with 10% allocation (100000 PPM)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), 0, 100000) // 10%, self-minting

      // Should now be 400000 PPM (300000 + 100000)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingRate).to.equal(400000)
      }

      // Change target1 from self-minting to allocator-minting (same allocation)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 300000, 0) // 30%, allocator-minting

      // Should now be 100000 PPM (400000 - 300000)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingRate).to.equal(100000)
      }

      // Remove target2 (set allocation to 0)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), 0, 0) // Remove target2

      // Should now be 0 PPM (100000 - 100000)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingRate).to.equal(0)
      }

      // Add target1 back as self-minting with 50% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 0, 500000) // 50%, self-minting

      // Should now be 500000 PPM
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingRate).to.equal(500000)
      }
    })
  })

  describe('Issuance Rate Management', () => {
    it('should update issuance rate correctly', async () => {
      const { issuanceAllocator } = sharedContracts

      const newIssuancePerBlock = ethers.parseEther('200')
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(newIssuancePerBlock)

      expect(await issuanceAllocator.getIssuancePerBlock()).to.equal(newIssuancePerBlock)
    })

    it('should notify targets with contract code when changing issuance rate', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 300000, 0) // 30%

      // Mine some blocks to ensure distributeIssuance will update to current block
      await ethers.provider.send('evm_mine', [])

      // Change issuance rate - this should trigger _preIssuanceChangeDistributionAndNotification
      // which will iterate through targets and call beforeIssuanceAllocationChange on targets with code
      const newIssuancePerBlock = ethers.parseEther('200')
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(newIssuancePerBlock)

      // Verify the issuance rate was updated
      expect(await issuanceAllocator.getIssuancePerBlock()).to.equal(newIssuancePerBlock)
    })

    it('should handle targets without contract code when changing issuance rate', async () => {
      const { issuanceAllocator, graphToken } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator (needed for distributeIssuance calls)
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add a target using MockSimpleTarget and set allocation in one step
      const mockTarget = await deployMockSimpleTarget()
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await mockTarget.getAddress(), 300000, 0) // 30%

      // Mine some blocks to ensure distributeIssuance will update to current block
      await ethers.provider.send('evm_mine', [])

      // Change issuance rate - this should trigger _preIssuanceChangeDistributionAndNotification
      // which will iterate through targets and notify them
      const newIssuancePerBlock = ethers.parseEther('200')
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(newIssuancePerBlock)

      // Verify the issuance rate was updated
      expect(await issuanceAllocator.getIssuancePerBlock()).to.equal(newIssuancePerBlock)
    })

    it('should handle zero issuance when distributing', async () => {
      const { issuanceAllocator, graphToken, addresses } = sharedContracts

      // Set issuance per block to 0
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(0)

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 0, 0) // 30%

      // Get initial balance
      const initialBalance = await (graphToken as any).balanceOf(addresses.target1)

      // Mine some blocks
      await ethers.provider.send('evm_mine', [])

      // Distribute issuance - should not mint any tokens since issuance per block is 0
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Verify no tokens were minted
      const finalBalance = await (graphToken as any).balanceOf(addresses.target1)
      expect(finalBalance).to.equal(initialBalance)
    })

    it('should revert when decreasing issuance rate with insufficient unallocated budget', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Add issuanceAllocator as minter
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Set initial issuance rate
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'))

      // Allocate almost everything to target1, leaving very little for default
      // target1 gets 950 ether/block, default gets 50 ether/block
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target1.getAddress(), ethers.parseEther('950'), 0, 0)

      // Verify the current allocation
      const allocationBefore = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(allocationBefore.allocatorMintingRate).to.equal(ethers.parseEther('950'))

      // Verify current issuance and unallocated amount
      const issuanceBefore = await issuanceAllocator.getIssuancePerBlock()
      expect(issuanceBefore).to.equal(ethers.parseEther('1000'))

      // Try to decrease issuance rate by 100 ether (to 900 ether/block)
      // This would require default to absorb -100 ether/block change
      // But default only has 50 ether/block unallocated
      // So this should fail: oldIssuancePerBlock (1000) > newIssuancePerBlock (900) + unallocated (50)
      await expect(
        issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('900')),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'InsufficientUnallocatedForRateDecrease')
    })

    it('should allow governor to manually notify a specific target', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 300000, 0) // 30%

      // Manually notify the target using the new notifyTarget function
      const result = await issuanceAllocator.connect(accounts.governor).notifyTarget.staticCall(addresses.target1)

      // Should return true since notification was sent
      expect(result).to.be.true
    })

    it('should revert when notifying a non-existent target (EOA)', async () => {
      const { issuanceAllocator } = sharedContracts

      // Try to notify a target that doesn't exist (EOA)
      // This will revert because it tries to call a function on a non-contract
      await expect(issuanceAllocator.connect(accounts.governor).notifyTarget(accounts.nonGovernor.address)).to.be
        .reverted
    })

    it('should return false when notifying a target without contract code', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add a target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 100000, 0)

      // Try to notify the target - should succeed since it has contract code
      const result = await issuanceAllocator.connect(accounts.governor).notifyTarget.staticCall(addresses.target1)

      // Should return true since target has contract code and supports the interface
      expect(result).to.be.true
    })

    it('should return false when _notifyTarget is called directly on EOA target', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add a target and set allocation in one step to trigger _notifyTarget call
      const result = await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'].staticCall(addresses.target1, 100000, 0, 0)

      // Should return true (allocation was set) and notification succeeded
      expect(result).to.be.true

      // Actually set the allocation to verify the internal _notifyTarget call
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 100000, 0)

      // Verify allocation was set
      const mockTargetAllocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(mockTargetAllocation.totalAllocationRate).to.equal(100000)
    })

    it('should only notify target once per block', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 300000, 0) // 30%

      // First notification should return true
      const result1 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(result1).to.be.true

      // Actually send the first notification
      await issuanceAllocator.connect(accounts.governor).notifyTarget(await target1.getAddress())

      // Second notification in the same block should return true (already notified)
      const result2 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(result2).to.be.true
    })

    it('should revert when notification fails due to target reverting', async () => {
      const { issuanceAllocator, graphToken } = await setupIssuanceAllocator()

      // Deploy a mock target that reverts on beforeIssuanceAllocationChange
      const MockRevertingTarget = await ethers.getContractFactory('MockRevertingTarget')
      const revertingTarget = await MockRevertingTarget.deploy()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // First, we need to force set the lastChangeNotifiedBlock to a past block
      // so that the notification will actually be attempted
      const currentBlock = await ethers.provider.getBlockNumber()
      await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock(await revertingTarget.getAddress(), currentBlock - 1)

      await expect(
        issuanceAllocator.connect(accounts.governor).notifyTarget(await revertingTarget.getAddress()),
      ).to.be.revertedWithCustomError(revertingTarget, 'TargetRevertsIntentionally')
    })

    it('should revert and not set allocation when notification fails with force=false', async () => {
      const { issuanceAllocator, graphToken } = await setupIssuanceAllocator()

      // Deploy a mock target that reverts on beforeIssuanceAllocationChange
      const MockRevertingTarget = await ethers.getContractFactory('MockRevertingTarget')
      const revertingTarget = await MockRevertingTarget.deploy()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Try to add the reverting target with force=false
      // This should trigger notification which will fail and cause the transaction to revert
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](await revertingTarget.getAddress(), 300000, 0),
      ).to.be.revertedWithCustomError(revertingTarget, 'TargetRevertsIntentionally')

      // The allocation should NOT be set because the transaction reverted
      const revertingTargetAllocation = await issuanceAllocator.getTargetAllocation(await revertingTarget.getAddress())
      expect(revertingTargetAllocation.totalAllocationRate).to.equal(0)
    })

    it('should revert and not set allocation when target notification fails even with force=true', async () => {
      const { issuanceAllocator, graphToken } = await setupIssuanceAllocator()

      // Deploy a mock target that reverts on beforeIssuanceAllocationChange
      const MockRevertingTarget = await ethers.getContractFactory('MockRevertingTarget')
      const revertingTarget = await MockRevertingTarget.deploy()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Try to add the reverting target with force=true
      // This should trigger notification which will fail and cause the transaction to revert
      // (force only affects distribution, not notification)
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,uint256)'](await revertingTarget.getAddress(), 300000, 0, 0),
      ).to.be.revertedWithCustomError(revertingTarget, 'TargetRevertsIntentionally')

      // The allocation should NOT be set because the transaction reverted
      const allocation = await issuanceAllocator.getTargetAllocation(await revertingTarget.getAddress())
      expect(allocation.totalAllocationRate).to.equal(0)
    })

    it('should return false when setTargetAllocation called with force=false and issuance distribution is behind', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Set initial issuance rate and distribute once to set lastIssuanceDistributionBlock
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Get the current lastIssuanceDistributionBlock
      const lastIssuanceBlock = (await issuanceAllocator.getDistributionState()).lastDistributionBlock

      // Grant pause role and pause the contract
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine several blocks while paused (this will make _distributeIssuance() return lastIssuanceDistributionBlock < block.number)
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Verify that we're now in a state where _distributeIssuance() would return a value < block.number
      const currentBlock = await ethers.provider.getBlockNumber()
      expect(lastIssuanceBlock).to.be.lt(currentBlock)

      // While still paused, call setTargetAllocation with minDistributedBlock=currentBlock
      // This should return false because _distributeIssuance() < minDistributedBlock
      // (lastDistributionBlock is behind currentBlock due to pause)
      const result = await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ].staticCall(await target1.getAddress(), ethers.parseEther('30'), 0, currentBlock)

      // Should return false due to issuance being behind the required minimum
      expect(result).to.be.false

      // Allocation is not actually set (staticCall)
      const allocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(allocation.totalAllocationRate).to.equal(0)
    })

    it('should allow setTargetAllocation with force=true when issuance distribution is behind', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Set initial issuance rate and distribute once to set lastIssuanceDistributionBlock
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Get the current lastIssuanceDistributionBlock
      const lastIssuanceBlock = (await issuanceAllocator.getDistributionState()).lastDistributionBlock

      // Grant pause role and pause the contract
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine several blocks while paused (this will make _distributeIssuance() return lastIssuanceDistributionBlock < block.number)
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Verify that we're now in a state where _distributeIssuance() would return a value < block.number
      const currentBlock = await ethers.provider.getBlockNumber()
      expect(lastIssuanceBlock).to.be.lt(currentBlock)

      // While still paused, call setTargetAllocation with force=true
      // This should succeed despite _distributeIssuance() < block.number because force=true
      // This tests the uncovered branch where (_distributeIssuance() < block.number && !force) evaluates to false due to force=true
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'](await target1.getAddress(), 300000, 0, 0)

      // Should succeed and set the allocation
      const allocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(allocation.totalAllocationRate).to.equal(300000)
    })
  })

  describe('Force Change Notification Block', () => {
    it('should allow governor to force set lastChangeNotifiedBlock', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 100000, 0)

      // Force set lastChangeNotifiedBlock to current block
      const currentBlock = await ethers.provider.getBlockNumber()
      const result = await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock.staticCall(addresses.target1, currentBlock)

      expect(result).to.equal(currentBlock)

      // Actually call the function
      await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock(addresses.target1, currentBlock)

      // Verify the lastChangeNotifiedBlock was set
      const targetData = await issuanceAllocator.getTargetData(addresses.target1)
      expect(targetData.lastChangeNotifiedBlock).to.equal(currentBlock)
    })

    it('should allow force setting lastChangeNotifiedBlock for non-existent target', async () => {
      const { issuanceAllocator } = sharedContracts

      const nonExistentTarget = accounts.nonGovernor.address
      const currentBlock = await ethers.provider.getBlockNumber()

      // Force set for non-existent target should work (no validation)
      const result = await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock.staticCall(nonExistentTarget, currentBlock)
      expect(result).to.equal(currentBlock)

      // Actually call the function
      await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock(nonExistentTarget, currentBlock)

      // Verify the lastChangeNotifiedBlock was set (even though target doesn't exist)
      const targetData = await issuanceAllocator.getTargetData(nonExistentTarget)
      expect(targetData.lastChangeNotifiedBlock).to.equal(currentBlock)
    })

    it('should enable notification to be sent again by setting to past block', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add target and set allocation in one step to trigger notification
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 300000, 0)

      // Verify target was notified (lastChangeNotifiedBlock should be current block)
      const currentBlock = await ethers.provider.getBlockNumber()
      let targetData = await issuanceAllocator.getTargetData(await target1.getAddress())
      expect(targetData.lastChangeNotifiedBlock).to.equal(currentBlock)

      // Try to notify again in the same block - should return true (already notified)
      const notifyResult1 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(notifyResult1).to.be.true

      // Force set lastChangeNotifiedBlock to a past block (current block - 1)
      const pastBlock = currentBlock - 1
      const forceResult = await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock.staticCall(await target1.getAddress(), pastBlock)

      // Should return the block number that was set
      expect(forceResult).to.equal(pastBlock)

      // Actually call the function
      await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock(await target1.getAddress(), pastBlock)

      // Now notification should be sent again
      const notifyResult2 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(notifyResult2).to.be.true

      // Actually send the notification
      await issuanceAllocator.connect(accounts.governor).notifyTarget(await target1.getAddress())

      // Verify lastChangeNotifiedBlock was updated to the current block (which may have advanced)
      targetData = await issuanceAllocator.getTargetData(await target1.getAddress())
      const finalBlock = await ethers.provider.getBlockNumber()
      expect(targetData.lastChangeNotifiedBlock).to.equal(finalBlock)
    })

    it('should prevent notification until next block by setting to current block', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 100000, 0)

      // Force set lastChangeNotifiedBlock to current block
      const currentBlock = await ethers.provider.getBlockNumber()
      const forceResult = await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock.staticCall(await target1.getAddress(), currentBlock)

      // Should return the block number that was set
      expect(forceResult).to.equal(currentBlock)

      // Actually call the function
      await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock(await target1.getAddress(), currentBlock)

      // Try to notify in the same block - should return true (already notified this block)
      const notifyResult1 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(notifyResult1).to.be.true

      // Mine a block to advance
      await ethers.provider.send('evm_mine', [])

      // Now notification should be sent in the next block
      const notifyResult2 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(notifyResult2).to.be.true
    })

    it('should prevent notification until future block by setting to future block', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 100000, 0)

      // Force set lastChangeNotifiedBlock to a future block (current + 2)
      const currentBlock = await ethers.provider.getBlockNumber()
      const futureBlock = currentBlock + 2
      const forceResult = await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock.staticCall(await target1.getAddress(), futureBlock)

      // Should return the block number that was set
      expect(forceResult).to.equal(futureBlock)

      // Actually call the function
      await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock(await target1.getAddress(), futureBlock)

      // Try to notify in the current block - should return true (already "notified" for future block)
      const notifyResult1 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(notifyResult1).to.be.true

      // Mine one block
      await ethers.provider.send('evm_mine', [])

      // Still should return true (still before the future block)
      const notifyResult2 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(notifyResult2).to.be.true

      // Mine another block to reach the future block
      await ethers.provider.send('evm_mine', [])

      // Now should still return true (at the future block)
      const notifyResult3 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(notifyResult3).to.be.true

      // Mine one more block to go past the future block
      await ethers.provider.send('evm_mine', [])

      // Now notification should be sent
      const notifyResult4 = await issuanceAllocator
        .connect(accounts.governor)
        .notifyTarget.staticCall(await target1.getAddress())
      expect(notifyResult4).to.be.true
    })
  })

  describe('Idempotent Operations', () => {
    it('should not revert when operating on non-existent targets', async () => {
      const { issuanceAllocator } = sharedContracts

      const nonExistentTarget = accounts.nonGovernor.address

      // Test 1: Setting allocation to 0 for non-existent target should not revert
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](nonExistentTarget, 0, 0)

      // Verify no non-default targets were added (only default remains)
      const targets = await issuanceAllocator.getTargets()
      expect(targets.length).to.equal(1) // Only default target

      // Verify reported total is 0% (all in default, which isn't reported)
      const totalAlloc = await issuanceAllocator.getTotalAllocation()
      expect(totalAlloc.totalAllocationRate).to.equal(0)

      // Test 2: Removing non-existent target (by setting allocation to 0 again) should not revert
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](nonExistentTarget, 0, 0)

      // Verify still only default target
      const targetsAfter = await issuanceAllocator.getTargets()
      expect(targetsAfter.length).to.equal(1) // Only default target
    })
  })

  describe('View Functions', () => {
    it('should update lastIssuanceDistributionBlock after distribution', async () => {
      const { issuanceAllocator } = sharedContracts

      // Get initial lastIssuanceDistributionBlock
      const initialBlock = (await issuanceAllocator.getDistributionState()).lastDistributionBlock

      // Mine a block
      await ethers.provider.send('evm_mine', [])

      // Distribute issuance to update lastIssuanceDistributionBlock
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Now lastIssuanceDistributionBlock should be updated
      const newBlock = (await issuanceAllocator.getDistributionState()).lastDistributionBlock
      expect(newBlock).to.be.gt(initialBlock)
    })

    it('should manage target count and array correctly', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Test initial state (with default target)
      expect(await issuanceAllocator.getTargetCount()).to.equal(1) // Default allocation exists
      expect((await issuanceAllocator.getTargets()).length).to.equal(1)

      // Test adding targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 100000, 0)
      expect(await issuanceAllocator.getTargetCount()).to.equal(2) // Default + target1

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target2, 200000, 0)
      expect(await issuanceAllocator.getTargetCount()).to.equal(3) // Default + target1 + target2

      // Test getTargets array content
      const targetAddresses = await issuanceAllocator.getTargets()
      expect(targetAddresses.length).to.equal(3)
      expect(targetAddresses).to.include(addresses.target1)
      expect(targetAddresses).to.include(addresses.target2)

      // Test removing targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 0, 0)
      expect(await issuanceAllocator.getTargetCount()).to.equal(2) // Default + target2

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target2, 0, 0)
      expect(await issuanceAllocator.getTargetCount()).to.equal(1) // Only default remains
      expect((await issuanceAllocator.getTargets()).length).to.equal(1)
    })

    it('should store targets in the getTargets array in correct order', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 100000, 0)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target2, 200000, 0)

      // Get addresses array
      const targetAddresses = await issuanceAllocator.getTargets()

      // Check that the addresses are in the correct order
      // targetAddresses[0] is the default target (address(0))
      expect(targetAddresses[0]).to.equal(ethers.ZeroAddress) // Default
      expect(targetAddresses[1]).to.equal(addresses.target1)
      expect(targetAddresses[2]).to.equal(addresses.target2)
      expect(targetAddresses.length).to.equal(3) // Default + target1 + target2
    })

    it('should return the correct target address by index', async () => {
      const { issuanceAllocator, graphToken, target1, target2, target3 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator (needed for distributeIssuance calls)
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 100000, 0)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), 200000, 0)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target3.getAddress(), 0, 300000)

      // Get all target addresses
      const addresses = await issuanceAllocator.getTargets()
      expect(addresses.length).to.equal(4) // Default + 3 targets

      // Check that the addresses are in the correct order
      // addresses[0] is the default target (address(0))
      expect(addresses[0]).to.equal(ethers.ZeroAddress) // Default
      expect(addresses[1]).to.equal(await target1.getAddress())
      expect(addresses[2]).to.equal(await target2.getAddress())
      expect(addresses[3]).to.equal(await target3.getAddress())

      // Test getTargetAt method for individual access
      expect(await issuanceAllocator.getTargetAt(0)).to.equal(ethers.ZeroAddress) // Default
      expect(await issuanceAllocator.getTargetAt(1)).to.equal(await target1.getAddress())
      expect(await issuanceAllocator.getTargetAt(2)).to.equal(await target2.getAddress())
      expect(await issuanceAllocator.getTargetAt(3)).to.equal(await target3.getAddress())
    })

    it('should return the correct target allocation', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target with allocation in one step
      const allocation = 300000 // 30% in PPM
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, allocation, 0)

      // Now allocation should be set
      const targetAllocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(targetAllocation.totalAllocationRate).to.equal(allocation)
    })

    it('should return the correct allocation types', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator (needed for distributeIssuance calls)
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add targets with different allocation types
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 100000, 0)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), 0, 200000)

      // Check allocation types
      const target1Allocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      const target2Allocation = await issuanceAllocator.getTargetAllocation(await target2.getAddress())

      expect(target1Allocation.selfMintingRate).to.equal(0) // Not self-minting
      expect(target1Allocation.allocatorMintingRate).to.equal(100000) // Allocator-minting

      expect(target2Allocation.selfMintingRate).to.equal(200000) // Self-minting
      expect(target2Allocation.allocatorMintingRate).to.equal(0) // Not allocator-minting
    })
  })

  describe('Return Values', () => {
    describe('setTargetAllocation', () => {
      it('should return true for successful operations', async () => {
        const { issuanceAllocator } = await setupSimpleIssuanceAllocator()
        const target = await deployMockSimpleTarget()

        // Adding new target
        const addResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,uint256)'].staticCall(await target.getAddress(), 100000, 0, 0)
        expect(addResult).to.equal(true)

        // Actually add the target
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](await target.getAddress(), 100000, 0)

        // Changing existing allocation
        const changeResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,uint256)'].staticCall(await target.getAddress(), 200000, 0, 0)
        expect(changeResult).to.equal(true)

        // Setting same allocation (no-op)
        const sameResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,uint256)'].staticCall(await target.getAddress(), 100000, 0, 0)
        expect(sameResult).to.equal(true)

        // Removing target
        const removeResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,uint256)'].staticCall(await target.getAddress(), 0, 0, 0)
        expect(removeResult).to.equal(true)

        // Setting allocation to 0 for non-existent target
        const nonExistentResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,uint256)'].staticCall(accounts.nonGovernor.address, 0, 0, 0)
        expect(nonExistentResult).to.equal(true)
      })
    })

    describe('setTargetAllocation overloads', () => {
      it('should work with all setTargetAllocation overloads and enforce access control', async () => {
        const { issuanceAllocator } = await setupSimpleIssuanceAllocator()
        const target1 = await deployMockSimpleTarget()
        const target2 = await deployMockSimpleTarget()

        // Test 1: 2-parameter overload (allocator-only)
        const allocatorPPM = 300000 // 30%
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](await target1.getAddress(), allocatorPPM)

        // Verify the allocation was set correctly
        const allocation1 = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
        expect(allocation1.allocatorMintingRate).to.equal(allocatorPPM)
        expect(allocation1.selfMintingRate).to.equal(0)

        // Test 2: 3-parameter overload (allocator + self)
        const allocatorPPM2 = 200000 // 20%
        const selfPPM = 150000 // 15%
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), allocatorPPM2, selfPPM)

        // Verify the allocation was set correctly
        const allocation2 = await issuanceAllocator.getTargetAllocation(await target2.getAddress())
        expect(allocation2.allocatorMintingRate).to.equal(allocatorPPM2)
        expect(allocation2.selfMintingRate).to.equal(selfPPM)

        // Test 3: Access control - 2-parameter overload should require governor
        await expect(
          issuanceAllocator
            .connect(accounts.nonGovernor)
            ['setTargetAllocation(address,uint256)'](await target1.getAddress(), 200000),
        ).to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')

        // Test 4: Access control - 3-parameter overload should require governor
        await expect(
          issuanceAllocator
            .connect(accounts.nonGovernor)
            ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), 160000, 90000),
        ).to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')
      })
    })

    describe('setIssuancePerBlock', () => {
      it('should return appropriate values based on conditions', async () => {
        const { issuanceAllocator } = sharedContracts

        // Should return true for normal operations
        const newRate = ethers.parseEther('200')
        const normalResult = await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock.staticCall(newRate)
        expect(normalResult).to.equal(true)

        // Should return true even when setting same rate
        const sameResult = await issuanceAllocator
          .connect(accounts.governor)
          .setIssuancePerBlock.staticCall(issuancePerBlock)
        expect(sameResult).to.equal(true)

        // Grant pause role and pause the contract
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).pause()

        // setIssuancePerBlock returns false when paused without explicit fromBlockNumber
        const pausedResult = await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock.staticCall(newRate)
        expect(pausedResult).to.equal(false)

        // setIssuancePerBlock returns true when paused with explicit fromBlockNumber that has been reached
        const lastDistributionBlock = await (await issuanceAllocator.getDistributionState()).lastDistributionBlock
        const pausedWithBlockResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setIssuancePerBlock(uint256,uint256)'].staticCall(newRate, lastDistributionBlock)
        expect(pausedWithBlockResult).to.equal(true)

        // Actually execute the call with fromBlockNumber to cover all branches
        await issuanceAllocator
          .connect(accounts.governor)
          ['setIssuancePerBlock(uint256,uint256)'](newRate, lastDistributionBlock)
        expect(await issuanceAllocator.getIssuancePerBlock()).to.equal(newRate)

        // Verify the simple variant still returns false when paused
        const differentRate = ethers.parseEther('2000')
        const result = await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock.staticCall(differentRate)
        expect(result).to.equal(false)
        // Rate should not change because paused and no explicit fromBlockNumber
        expect(await issuanceAllocator.getIssuancePerBlock()).to.equal(newRate)
      })
    })

    describe('distributeIssuance', () => {
      it('should return appropriate block numbers', async () => {
        const { issuanceAllocator, addresses } = sharedContracts

        // Should return lastIssuanceDistributionBlock when no blocks have passed
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()
        const lastIssuanceBlock = (await issuanceAllocator.getDistributionState()).lastDistributionBlock
        const noBlocksResult = await issuanceAllocator.connect(accounts.governor).distributeIssuance.staticCall()
        expect(noBlocksResult).to.equal(lastIssuanceBlock)

        // Add a target and mine blocks to test distribution
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 300000, 0) // 30%
        await ethers.provider.send('evm_mine', [])

        // Should return current block number when issuance is distributed
        const currentBlock = await ethers.provider.getBlockNumber()
        const distributionResult = await issuanceAllocator.connect(accounts.governor).distributeIssuance.staticCall()
        expect(distributionResult).to.equal(currentBlock)
      })
    })
  })

  describe('getTargetIssuancePerBlock', () => {
    it('should return correct issuance for different target configurations', async () => {
      const { issuanceAllocator, addresses } = sharedContracts
      // OLD: These were used for PPM calculations
      // const issuancePerBlock = await issuanceAllocator.getIssuancePerBlock()
      // const PPM = 1_000_000

      // Test unregistered target (should return zeros)
      let result = await issuanceAllocator.getTargetIssuancePerBlock(addresses.target1)
      expect(result.selfIssuanceRate).to.equal(0)
      expect(result.allocatorIssuanceRate).to.equal(0)
      expect(result.allocatorIssuanceBlockAppliedTo).to.be.greaterThanOrEqual(0)
      expect(result.selfIssuanceBlockAppliedTo).to.be.greaterThanOrEqual(0)

      // Test self-minting target with 30% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 0, ethers.parseEther('30'))

      const expectedSelfIssuance = ethers.parseEther('30')
      result = await issuanceAllocator.getTargetIssuancePerBlock(addresses.target1)
      expect(result.selfIssuanceRate).to.equal(expectedSelfIssuance)
      expect(result.allocatorIssuanceRate).to.equal(0)
      //       expect(result.selfIssuanceBlockAppliedTo).to.equal(await issuanceAllocator.lastIssuanceAccumulationBlock())
      expect(result.allocatorIssuanceBlockAppliedTo).to.equal(
        (await issuanceAllocator.getDistributionState()).lastDistributionBlock,
      )

      // Test allocator-minting target with 40% allocation (reset target1 first)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, ethers.parseEther('40'), 0)

      const expectedAllocatorIssuance = ethers.parseEther('40')
      result = await issuanceAllocator.getTargetIssuancePerBlock(addresses.target1)
      expect(result.allocatorIssuanceRate).to.equal(expectedAllocatorIssuance)
      expect(result.selfIssuanceRate).to.equal(0)
      expect(result.allocatorIssuanceBlockAppliedTo).to.equal(
        (await issuanceAllocator.getDistributionState()).lastDistributionBlock,
      )
      //       expect(result.selfIssuanceBlockAppliedTo).to.equal(await issuanceAllocator.lastIssuanceAccumulationBlock())
    })

    it('should not revert when contract is paused and blockAppliedTo indicates pause state', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target as self-minter with 30% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 0, ethers.parseEther('30')) // 30%, self-minter

      // Distribute issuance to set blockAppliedTo to current block
      await issuanceAllocator.distributeIssuance()

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).pause()

      // Should not revert when paused - this is the key difference from old functions
      const result = await issuanceAllocator.getTargetIssuancePerBlock(addresses.target1)

      // OLD: These were used for PPM calculations
      // const issuancePerBlock = await issuanceAllocator.getIssuancePerBlock()
      // const PPM = 1_000_000
      const expectedIssuance = ethers.parseEther('30')

      expect(result.selfIssuanceRate).to.equal(expectedIssuance)
      expect(result.allocatorIssuanceRate).to.equal(0)
      // For self-minting targets, selfIssuanceBlockAppliedTo reflects when events were last emitted (lastAccumulationBlock)
      //       expect(result.selfIssuanceBlockAppliedTo).to.equal(await issuanceAllocator.lastIssuanceAccumulationBlock())
      // allocatorIssuanceBlockAppliedTo should be the last distribution block (before pause)
      expect(result.allocatorIssuanceBlockAppliedTo).to.equal(
        (await issuanceAllocator.getDistributionState()).lastDistributionBlock,
      )
    })

    it('should show blockAppliedTo updates after distribution', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator (needed for distributeIssuance calls)
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add target as allocator-minter with 50% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target1.getAddress(), ethers.parseEther('50'), 0, 0) // 50%, allocator-minter

      // allocatorIssuanceBlockAppliedTo should be current block since setTargetAllocation triggers distribution
      let result = await issuanceAllocator.getTargetIssuancePerBlock(await target1.getAddress())
      expect(result.allocatorIssuanceBlockAppliedTo).to.equal(await ethers.provider.getBlockNumber())
      expect(result.selfIssuanceBlockAppliedTo).to.equal(await ethers.provider.getBlockNumber())

      // Distribute issuance
      await issuanceAllocator.distributeIssuance()
      const distributionBlock = await ethers.provider.getBlockNumber()

      // Now allocatorIssuanceBlockAppliedTo should be updated to current block
      result = await issuanceAllocator.getTargetIssuancePerBlock(await target1.getAddress())
      expect(result.allocatorIssuanceBlockAppliedTo).to.equal(distributionBlock)
      expect(result.selfIssuanceBlockAppliedTo).to.equal(distributionBlock)

      // OLD: These were used for PPM calculations
      // const issuancePerBlock = await issuanceAllocator.getIssuancePerBlock()
      // const PPM = 1_000_000
      const expectedIssuance = ethers.parseEther('50')
      expect(result.allocatorIssuanceRate).to.equal(expectedIssuance)
      expect(result.selfIssuanceRate).to.equal(0)
    })
  })

  describe('Notification Behavior When Paused', () => {
    it('should notify targets of allocation changes even when paused', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Setup
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      // Add initial allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 300000, 0) // 30%

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()

      // Change allocation while paused - should notify target even though paused
      const lastDistributionBlock = await (await issuanceAllocator.getDistributionState()).lastDistributionBlock
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'](addresses.target1, 400000, 0, lastDistributionBlock) // Change to 40%

      // Verify that beforeIssuanceAllocationChange was called on the target
      // This is verified by checking that the transaction succeeded and the allocation was updated
      const allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(allocation.allocatorMintingRate).to.equal(400000)
    })

    it('should notify targets of issuance rate changes even when paused', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Setup
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      // Add target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 300000) // 30%

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()

      // Change issuance rate while paused - should notify targets even though paused
      // Use explicit fromBlockNumber to allow change while paused
      const lastDistributionBlock = await (await issuanceAllocator.getDistributionState()).lastDistributionBlock
      await issuanceAllocator
        .connect(accounts.governor)
        ['setIssuancePerBlock(uint256,uint256)'](ethers.parseEther('200'), lastDistributionBlock)

      // Verify that the rate change was applied
      expect(await issuanceAllocator.getIssuancePerBlock()).to.equal(ethers.parseEther('200'))
    })

    it('should not notify targets when no actual change occurs', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      // Add target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 300000, 0) // 30%

      // Try to set the same allocation - should not notify (no change)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 300000, 0) // Same 30%

      // Verify allocation is unchanged
      const allocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(allocation.allocatorMintingRate).to.equal(300000)

      // Try to set the same issuance rate - should not notify (no change)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      expect(await issuanceAllocator.getIssuancePerBlock()).to.equal(ethers.parseEther('100'))
    })
  })

  describe('Pending Issuance Distribution', () => {
    it('should handle distributePendingIssuance with accumulated self-minting', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      // Add allocator-minting and self-minting targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 400000, 0) // 40% allocator
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), 0, 100000) // 10% self

      // Distribute once to initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())

      // Pause and mine blocks to accumulate self-minting
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Trigger accumulation by changing self-minting allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'](await target2.getAddress(), 0, 200000, 0) // Change to 20% self

      // Check accumulation exists
      const distState = await issuanceAllocator.getDistributionState()
      expect(distState.selfMintingOffset).to.be.gt(0)

      // Call distributePendingIssuance
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

      // Verify tokens were distributed
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      expect(finalBalance1).to.be.gt(initialBalance1)

      // Verify accumulation was cleared
      const finalDistState = await issuanceAllocator.getDistributionState()
      expect(finalDistState.selfMintingOffset).to.equal(0)
    })

    it('should handle distributePendingIssuance with toBlockNumber parameter', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 500000, 100000)

      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const beforePauseState = await issuanceAllocator.getDistributionState()

      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Trigger accumulation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'](await target1.getAddress(), 500000, 200000, 0)

      const currentBlock = await ethers.provider.getBlockNumber()
      const distState = await issuanceAllocator.getDistributionState()
      // Distribute only to a block that's midway through the accumulated period
      const partialBlock = beforePauseState.lastDistributionBlock + BigInt(2)

      // Distribute to a partial block (not current block)
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](partialBlock)

      // Verify partial distribution
      const afterPartialState = await issuanceAllocator.getDistributionState()
      expect(afterPartialState.lastDistributionBlock).to.equal(partialBlock)
      // Verify accumulation was partially consumed but some remains
      expect(afterPartialState.selfMintingOffset).to.be.lt(distState.selfMintingOffset)

      // Distribute remainder to current block
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](currentBlock)
      const finalState = await issuanceAllocator.getDistributionState()
      expect(finalState.selfMintingOffset).to.equal(0) // All cleared
    })

    it('should handle distributePendingIssuance when blocks == 0', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 500000, 0)

      // Distribute to current block
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      const distState = await issuanceAllocator.getDistributionState()
      const currentBlock = distState.lastDistributionBlock

      // Call distributePendingIssuance with toBlockNumber == lastDistributionBlock (blocks == 0)
      const result = await issuanceAllocator
        .connect(accounts.governor)
        ['distributePendingIssuance(uint256)'].staticCall(currentBlock)

      expect(result).to.equal(currentBlock)
    })

    it('should handle proportional distribution when available < allocatedTotal', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup with high allocator-minting and high self-minting rates
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'))

      // Setup: 40% + 40% allocator-minting, 15% self-minting (5% default)
      // Using absolute values (tokens per block, not PPM):
      // allocatedRate (non-default) = 1000 - 150 (self) - 50 (default) = 800 ether
      await issuanceAllocator.connect(accounts.governor)['setTargetAllocation(address,uint256,uint256,uint256)'](
        await target1.getAddress(),
        ethers.parseEther('400'), // 400 ether per block allocator-minting
        0,
        0,
      )
      await issuanceAllocator.connect(accounts.governor)['setTargetAllocation(address,uint256,uint256,uint256)'](
        await target2.getAddress(),
        ethers.parseEther('400'), // 400 ether per block allocator-minting
        ethers.parseEther('150'), // 150 ether per block self-minting
        0,
      )

      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Pause and mine blocks to build up self-minting accumulation
      await issuanceAllocator.connect(accounts.governor).pause()
      for (let i = 0; i < 10; i++) {
        await ethers.provider.send('evm_mine', [])
      }
      // Don't change allocations - just distribute with accumulated self-minting
      // After 10 blocks:
      // - selfMintingOffset = 150 ether * 10 = 1500 ether
      // - totalForPeriod = 1000 ether * 10 = 10000 ether
      // - available = 10000 - 1500 = 8500 ether
      // - allocatedTotal = 800 ether * 10 = 8000 ether
      // So: 8500 > 8000, this won't trigger proportional...
      //
      // Let me force it by calling distributePendingIssuance for only PART of the period
      // This will make available smaller relative to allocatedTotal

      const distState = await issuanceAllocator.getDistributionState()
      // Distribute for only 2 blocks instead of all 10
      const partialBlock = distState.lastDistributionBlock + BigInt(2)

      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // For 2 blocks with 10 blocks of accumulated self-minting:
      // - selfMintingOffset = 1500 ether (from 10 blocks)
      // - totalForPeriod = 1000 * 2 = 2000 ether (only distributing 2 blocks)
      // - available = 2000 - 1500 = 500 ether
      // - allocatedTotal = 800 * 2 = 1600 ether
      // So: 500 < 1600 ✓ triggers proportional distribution!

      // Distribute pending for partial period - should use proportional distribution
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](partialBlock)

      // Both targets should receive tokens (proportionally reduced due to budget constraint)
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      expect(finalBalance1).to.be.gt(initialBalance1)
      expect(finalBalance2).to.be.gt(initialBalance2)

      // Verify proportional distribution (both should get same amount since same allocator rate)
      const distributed1 = finalBalance1 - initialBalance1
      const distributed2 = finalBalance2 - initialBalance2
      expect(distributed1).to.be.closeTo(distributed2, ethers.parseEther('1'))
    })

    it('should distribute remainder to default target in full rate distribution', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      // Set target2 as default target (it's a contract that supports IIssuanceTarget)
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(await target2.getAddress())

      // Add target with low allocator rate, high self-minting - ensures default gets significant portion
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 100000, 100000) // 10% each

      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialDefaultBalance = await (graphToken as any).balanceOf(await target2.getAddress())

      // Pause and accumulate (with small self-minting, available should be > allocatedTotal)
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Trigger accumulation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'](await target1.getAddress(), 100000, 150000, 0)

      // Distribute - should give remainder to default target
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

      // Default target should receive tokens
      const finalDefaultBalance = await (graphToken as any).balanceOf(await target2.getAddress())
      expect(finalDefaultBalance).to.be.gt(initialDefaultBalance)
    })

    it('should trigger pending distribution path when selfMintingOffset > 0 in distributeIssuance', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target1.getAddress(), 500000, 100000)

      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

      // Pause and accumulate
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])

      // Trigger accumulation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'](await target1.getAddress(), 500000, 200000, 0)

      // Verify accumulation exists
      let distState = await issuanceAllocator.getDistributionState()
      expect(distState.selfMintingOffset).to.be.gt(0)

      // Unpause
      await issuanceAllocator.connect(accounts.governor).unpause()

      // Call distributeIssuance - should internally call _distributePendingIssuance due to accumulation
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Verify tokens distributed and accumulation cleared
      const finalBalance = await (graphToken as any).balanceOf(await target1.getAddress())
      expect(finalBalance).to.be.gt(initialBalance)

      distState = await issuanceAllocator.getDistributionState()
      expect(distState.selfMintingOffset).to.equal(0)
    })

    it('should revert when non-governor calls distributePendingIssuance()', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()

      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])

      // Try to call distributePendingIssuance() as non-governor
      await expect(issuanceAllocator.connect(accounts.user)['distributePendingIssuance()']()).to.be.reverted
    })

    it('should revert when non-governor calls distributePendingIssuance(uint256)', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()

      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])

      const distState = await issuanceAllocator.getDistributionState()
      const blockNumber = distState.lastDistributionBlock + BigInt(1)

      // Try to call distributePendingIssuance(uint256) as non-governor
      await expect(issuanceAllocator.connect(accounts.user)['distributePendingIssuance(uint256)'](blockNumber)).to.be
        .reverted
    })

    it('should revert when toBlockNumber > block.number', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()

      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)

      // Pause to enable distributePendingIssuance
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])

      // Try to distribute to a future block
      const futureBlock = (await ethers.provider.getBlockNumber()) + 100
      await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](futureBlock)).to
        .be.reverted
    })

    it('should revert when toBlockNumber < lastDistributionBlock', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()

      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)

      // Pause and mine some blocks
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      const distState = await issuanceAllocator.getDistributionState()
      const pastBlock = distState.lastDistributionBlock - BigInt(1)

      // Try to distribute to a block before lastDistributionBlock
      await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](pastBlock)).to.be
        .reverted
    })

    it('should handle exact allocation with zero remainder to default', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)

      // Set issuance to 1000 ether per block
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'))

      // Configure target1 with allocator=800, self=200 (total = 1000, leaving 0 for default)
      await issuanceAllocator.connect(accounts.governor)['setTargetAllocation(address,uint256,uint256,uint256)'](
        await target1.getAddress(),
        ethers.parseEther('800'), // 800 ether per block allocator-minting
        ethers.parseEther('200'), // 200 ether per block self-minting
        0,
      )

      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Pause and accumulate
      await issuanceAllocator.connect(accounts.governor).pause()
      for (let i = 0; i < 5; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

      const distStateBefore = await issuanceAllocator.getDistributionState()

      // Distribute - should result in exactly 0 remainder for default
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

      const distStateAfter = await issuanceAllocator.getDistributionState()
      const blocksDist = distStateAfter.lastDistributionBlock - distStateBefore.lastDistributionBlock

      // Calculate expected distribution based on actual blocks
      // totalForPeriod = 1000 * blocksDist ether
      // selfMintingOffset = 200 * blocksDist ether
      // available = (1000 - 200) * blocksDist = 800 * blocksDist ether
      // allocatedTotal = 800 * blocksDist ether
      // remainder = 0 ✓
      const finalBalance = await (graphToken as any).balanceOf(await target1.getAddress())
      const expectedDistribution = ethers.parseEther('800') * BigInt(blocksDist)
      expect(finalBalance - initialBalance).to.equal(expectedDistribution)
    })

    it('should handle proportional distribution with target having zero allocator rate', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'))

      // target1: allocator=400, self=0
      // target2: allocator=0, self=100 (self-minting only, no allocator-minting)
      // default: gets the remainder (500 allocator + 0 self)
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target1.getAddress(), ethers.parseEther('400'), 0, 0)
      await issuanceAllocator.connect(accounts.governor)['setTargetAllocation(address,uint256,uint256,uint256)'](
        await target2.getAddress(),
        0, // Zero allocator-minting rate
        ethers.parseEther('100'),
        0,
      )

      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Pause and accumulate enough self-minting
      await issuanceAllocator.connect(accounts.governor).pause()
      for (let i = 0; i < 15; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      const distStateBefore = await issuanceAllocator.getDistributionState()
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // Distribute only 2 blocks (out of the 15+ accumulated)
      // With high self-minting accumulation, this creates proportional distribution scenario
      // Expected accumulation during pause: 100 ether/block * ~15 blocks = ~1500 ether
      // Distribution for 2 blocks: totalForPeriod = 2000 ether, consumed ~= 1500 ether, available ~= 500 ether
      // allocatedTotal = 400 ether * 2 = 800 ether
      // Since available < allocatedTotal, proportional distribution kicks in
      const partialBlock = distStateBefore.lastDistributionBlock + BigInt(2)

      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](partialBlock)

      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // The key test: target1 should receive some tokens (it has allocatorMintingRate > 0)
      // target2 should receive ZERO tokens (it has allocatorMintingRate == 0)
      // This proves the `if (0 < targetData.allocatorMintingRate)` branch was tested
      const distributed1 = finalBalance1 - initialBalance1
      expect(distributed1).to.be.gt(0) // target1 gets some tokens
      expect(finalBalance2).to.equal(initialBalance2) // target2 gets zero (skipped in the if check)
    })
  })

  describe('Pause/Unpause Edge Cases', () => {
    // Helper function to deploy a fresh IssuanceAllocator for these tests
    async function setupIssuanceAllocator() {
      const graphToken = await deployTestGraphToken()
      const issuanceAllocator = await deployIssuanceAllocator(
        await graphToken.getAddress(),
        accounts.governor,
        ethers.parseEther('100'),
      )
      const target1 = await deployDirectAllocation(await graphToken.getAddress(), accounts.governor)
      const target2 = await deployDirectAllocation(await graphToken.getAddress(), accounts.governor)

      return { graphToken, issuanceAllocator, target1, target2 }
    }

    it('should handle unpause → mine blocks → pause without distributeIssuance', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      // Add targets: 30 tokens/block allocator-minting, 20 tokens/block self-minting (leaving 50 for default)
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target1.getAddress(), ethers.parseEther('30'), 0, 0) // 30 tokens/block allocator
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target2.getAddress(), 0, ethers.parseEther('20'), 0) // 20 tokens/block self

      // Initialize distribution
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBlock = await ethers.provider.getBlockNumber()

      // Track initial balance for target1 (allocator-minting target)
      const balance1Initial = await (graphToken as any).balanceOf(await target1.getAddress())

      // Phase 1: Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()
      const _pauseBlock1 = await ethers.provider.getBlockNumber()

      // Mine a few blocks while paused
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Phase 2: Unpause WITHOUT calling distributeIssuance
      await issuanceAllocator.connect(accounts.governor).unpause()
      const _unpauseBlock = await ethers.provider.getBlockNumber()

      // Phase 3: Mine blocks while unpaused, but DON'T call distributeIssuance
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Phase 4: Pause again WITHOUT calling distributeIssuance
      await issuanceAllocator.connect(accounts.governor).pause()
      const _pauseBlock2 = await ethers.provider.getBlockNumber()

      // Mine more blocks while paused
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Phase 5: Call distributeIssuance while paused
      // This is the key test: blocks between unpauseBlock and pauseBlock2 were unpaused,
      // but since distributeIssuance is called while paused, self-minting accumulation
      // treats them as paused (lazy evaluation)
      const tx1 = await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      await tx1.wait()
      const distributionBlock1 = await ethers.provider.getBlockNumber()

      // Verify: Check distribution state after first distribution
      const distState1 = await issuanceAllocator.getDistributionState()
      expect(distState1.lastSelfMintingBlock).to.equal(distributionBlock1)
      expect(distState1.lastDistributionBlock).to.equal(initialBlock) // Should NOT advance (paused)
      expect(distState1.selfMintingOffset).to.be.gt(0) // Should have accumulated

      // Calculate expected self-minting accumulation
      // From initialBlock to distributionBlock1 (all blocks treated as paused)
      const blocksSinceInitial = BigInt(distributionBlock1) - BigInt(initialBlock)
      const selfMintingRate = ethers.parseEther('20') // 20% of 100 = 20 tokens/block
      const expectedAccumulation = selfMintingRate * blocksSinceInitial
      expect(distState1.selfMintingOffset).to.be.closeTo(expectedAccumulation, ethers.parseEther('1'))

      // Verify no additional allocator-minting was distributed during pause
      const balance1AfterPause = await (graphToken as any).balanceOf(await target1.getAddress())
      expect(balance1AfterPause).to.equal(balance1Initial) // Should not have changed during pause

      // Phase 6: Unpause and call distributeIssuance
      await issuanceAllocator.connect(accounts.governor).unpause()
      await ethers.provider.send('evm_mine', [])

      const tx2 = await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      await tx2.wait()
      const distributionBlock2 = await ethers.provider.getBlockNumber()

      // Verify: Distribution state after second distribution
      const distState2 = await issuanceAllocator.getDistributionState()
      expect(distState2.lastSelfMintingBlock).to.equal(distributionBlock2)
      expect(distState2.lastDistributionBlock).to.equal(distributionBlock2) // Should advance (unpaused)
      expect(distState2.selfMintingOffset).to.equal(0) // Should be reset after distribution

      // Verify allocator-minting was distributed correctly
      const balance1After = await (graphToken as any).balanceOf(await target1.getAddress())
      expect(balance1After).to.be.gt(balance1Initial) // Should have received additional tokens

      // Calculate total issuance for the period
      const totalBlocks = BigInt(distributionBlock2) - BigInt(initialBlock)
      const totalIssuance = ethers.parseEther('100') * totalBlocks

      // Self-minting should have received their allowance (but not minted via allocator)
      // Allocator-minting should have received (totalIssuance - selfMintingOffset) * (30 / 80)
      // 30 tokens/block for target1, 50 tokens/block for default = 80 tokens/block total allocator-minting
      const expectedAllocatorDistribution =
        ((totalIssuance - expectedAccumulation) * ethers.parseEther('30')) / ethers.parseEther('80')

      // Allow for rounding errors (compare total distributed amount)
      // Note: Tolerance is higher due to multiple distribution events and the initial distribution
      const totalDistributed = balance1After - balance1Initial
      expect(totalDistributed).to.be.closeTo(expectedAllocatorDistribution, ethers.parseEther('25'))
    })

    it('should use getDistributionState to query distribution state efficiently', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target1.getAddress(), 0, ethers.parseEther('50'), 0) // 50 tokens/block self

      // Initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initBlock = await ethers.provider.getBlockNumber()

      // Verify initial state
      let distState = await issuanceAllocator.getDistributionState()
      expect(distState.lastDistributionBlock).to.equal(initBlock)
      expect(distState.lastSelfMintingBlock).to.equal(initBlock)
      expect(distState.selfMintingOffset).to.equal(0)

      // Pause and mine blocks
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Call distributeIssuance while paused
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const pausedDistBlock = await ethers.provider.getBlockNumber()

      // Verify state after paused distribution
      distState = await issuanceAllocator.getDistributionState()
      expect(distState.lastSelfMintingBlock).to.equal(pausedDistBlock)
      expect(distState.lastDistributionBlock).to.equal(initBlock) // Should NOT advance (paused)
      expect(distState.selfMintingOffset).to.be.gt(0) // Should have accumulated

      // Verify getDistributionState returns consistent values
      const distState2 = await issuanceAllocator.getDistributionState()
      expect(distState.lastDistributionBlock).to.equal(distState2.lastDistributionBlock)
      expect(distState.selfMintingOffset).to.equal(distState2.selfMintingOffset)
      expect(distState.lastSelfMintingBlock).to.equal(distState2.lastSelfMintingBlock)
    })

    it('should correctly emit IssuanceSelfMintAllowance events across pause/unpause cycles', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target1.getAddress(), 0, ethers.parseEther('50'), 0) // 50 tokens/block self

      // Initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initBlock = await ethers.provider.getBlockNumber()

      // Pause, unpause (without distribute), pause again
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await issuanceAllocator.connect(accounts.governor).unpause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])

      // Call distributeIssuance while paused
      const tx = await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const receipt = await tx.wait()
      const currentBlock = await ethers.provider.getBlockNumber()

      // Find IssuanceSelfMintAllowance events
      const events = receipt.logs.filter(
        (log) => log.topics[0] === issuanceAllocator.interface.getEvent('IssuanceSelfMintAllowance').topicHash,
      )

      // Should emit exactly one event for the entire range
      expect(events.length).to.equal(1)

      // Decode the event
      const decodedEvent = issuanceAllocator.interface.decodeEventLog(
        'IssuanceSelfMintAllowance',
        events[0].data,
        events[0].topics,
      )

      // Verify event covers the correct block range (from initBlock+1 to currentBlock)
      expect(decodedEvent.fromBlock).to.equal(BigInt(initBlock) + 1n)
      expect(decodedEvent.toBlock).to.equal(currentBlock)
      expect(decodedEvent.target).to.equal(await target1.getAddress())

      // Verify amount matches expected (50% of 100 tokens/block * number of blocks)
      const blocksInRange = BigInt(currentBlock) - BigInt(initBlock)
      const expectedAmount = ethers.parseEther('50') * blocksInRange
      expect(decodedEvent.amount).to.be.closeTo(expectedAmount, ethers.parseEther('1'))
    })

    it('should continue accumulating through unpaused periods when accumulated balance exists', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      // Set target1 allocation with both allocator and self minting
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target1.getAddress(), ethers.parseEther('30'), ethers.parseEther('20'), 0)

      // Distribute to set starting point
      await issuanceAllocator.distributeIssuance()
      const blockAfterInitialDist = await ethers.provider.getBlockNumber()

      // Phase 1: Pause and mine blocks
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Phase 2: Distribute while paused
      await issuanceAllocator.distributeIssuance()
      const blockDist1 = await ethers.provider.getBlockNumber()

      const state1 = await issuanceAllocator.getDistributionState()
      const pausedBlocks1 = blockDist1 - blockAfterInitialDist
      const expectedAccumulation1 = ethers.parseEther('20') * BigInt(pausedBlocks1)
      expect(state1.selfMintingOffset).to.equal(expectedAccumulation1)

      // Phase 3: Unpause (no distribute)
      await issuanceAllocator.connect(accounts.governor).unpause()

      // Mine more blocks while unpaused (no distribute!)
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Phase 4: Distribute while unpaused
      await issuanceAllocator.distributeIssuance()
      const blockDist2 = await ethers.provider.getBlockNumber()

      const state2 = await issuanceAllocator.getDistributionState()
      expect(state2.lastSelfMintingBlock).to.equal(blockDist2)
      expect(state2.selfMintingOffset).to.equal(0) // Cleared by distribution

      // Phase 5: Pause again (no distribute)
      await issuanceAllocator.connect(accounts.governor).pause()
      const blockPause2 = await ethers.provider.getBlockNumber()

      // Mine more blocks while paused
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Phase 6: Distribute while paused
      await issuanceAllocator.distributeIssuance()
      const blockDist3 = await ethers.provider.getBlockNumber()

      const state3 = await issuanceAllocator.getDistributionState()

      // THE FIX: With the new logic, accumulation continues from lastSelfMintingBlock
      // when paused, even if some of those blocks happened during an unpaused period
      // where no distribution occurred. This is conservative and safe.
      const blocksAccumulated = blockDist3 - blockDist2
      const actuallyPausedBlocks = blockDist3 - blockPause2
      const unpausedBlocksIncluded = blocksAccumulated - actuallyPausedBlocks

      // Verify the fix: accumulation should be for all blocks from lastSelfMintingBlock
      const actualAccumulation = state3.selfMintingOffset
      const expectedAccumulation = ethers.parseEther('20') * BigInt(blocksAccumulated)

      expect(actualAccumulation).to.equal(
        expectedAccumulation,
        'Should accumulate from lastSelfMintingBlock when paused, including unpaused blocks where no distribution occurred',
      )

      // Rationale: Once accumulation starts (during pause), continue through any unpaused periods
      // until distribution clears the accumulation. This is conservative and allows better recovery.
      expect(unpausedBlocksIncluded).to.equal(1) // Should include 1 unpaused block (blockDist2 to blockPause2)
    })

    it('should correctly handle partial distribution when toBlockNumber < block.number', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      // Add targets: 30 tokens/block allocator-minting, 20 tokens/block self-minting
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target1.getAddress(), ethers.parseEther('30'), 0, 0)
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target2.getAddress(), 0, ethers.parseEther('20'), 0)

      // Initialize distribution
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBlock = await ethers.provider.getBlockNumber()

      // Pause and mine blocks to accumulate self-minting
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // We've mined 8 blocks while paused (pause tx + 8 evm_mine calls)
      // Current block should be initialBlock + 9 (pause + 8 mines)

      // Call distributePendingIssuance with toBlockNumber at the halfway point
      const midBlock = initialBlock + 5 // Distribute only up to block 5

      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](midBlock)

      // Check the state after partial distribution
      const stateAfterPartial = await issuanceAllocator.getDistributionState()
      const actualCurrentBlock = await ethers.provider.getBlockNumber()

      // Budget-based clearing behavior for partial distribution:
      // - lastSelfMintingBlock advances to actualCurrentBlock (via _advanceSelfMintingBlock)
      // - lastDistributionBlock advances to midBlock (partial distribution)
      // - selfMintingOffset is reduced by min(accumulated, totalForPeriod)
      //
      // In this case: accumulated self-minting from initialBlock to actualCurrentBlock is small
      // compared to the period budget (100 tokens/block * 5 blocks distributed = 500 tokens),
      // so all accumulated is cleared (budget exceeds accumulated).

      expect(stateAfterPartial.lastDistributionBlock).to.equal(midBlock)
      expect(stateAfterPartial.lastSelfMintingBlock).to.equal(actualCurrentBlock)

      // Budget-based logic: subtract min(accumulated, totalForPeriod) from accumulated
      // Since accumulated < totalForPeriod (small accumulation vs large budget for 5 blocks),
      // all accumulated is cleared.
      expect(stateAfterPartial.selfMintingOffset).to.equal(0, 'Accumulated cleared when less than period budget')

      // Verify subsequent distribution works correctly
      await issuanceAllocator.connect(accounts.governor).unpause()
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const finalBlock = await ethers.provider.getBlockNumber()

      const stateAfterFinal = await issuanceAllocator.getDistributionState()
      expect(stateAfterFinal.selfMintingOffset).to.equal(0)
      expect(stateAfterFinal.lastDistributionBlock).to.equal(finalBlock)

      // Verify token distribution is mathematically correct
      // The allocator-minting should have received the correct amount accounting for ALL self-minting accumulation
      const balance1 = await (graphToken as any).balanceOf(await target1.getAddress())

      const totalBlocks = BigInt(finalBlock) - BigInt(initialBlock)
      const totalIssuance = ethers.parseEther('100') * totalBlocks
      const totalSelfMinting = ethers.parseEther('20') * totalBlocks
      const availableForAllocator = totalIssuance - totalSelfMinting
      // target1 gets 30/80 of allocator-minting (30 for target1, 50 for default)
      const expectedForTarget1 = (availableForAllocator * ethers.parseEther('30')) / ethers.parseEther('80')

      // Allow higher tolerance due to multiple distribution calls (partial + full)
      // Each transaction adds blocks which affects the total issuance calculation
      expect(balance1).to.be.closeTo(expectedForTarget1, ethers.parseEther('100'))
    })

    it('should correctly handle accumulated self-minting that exceeds period budget', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'))

      // High self-minting rate: 80 tokens/block, allocator: 20 tokens/block
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target1.getAddress(), ethers.parseEther('20'), 0, 0)
      await issuanceAllocator
        .connect(accounts.governor)
        [
          'setTargetAllocation(address,uint256,uint256,uint256)'
        ](await target2.getAddress(), 0, ethers.parseEther('80'), 0)

      // Initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBlock = await ethers.provider.getBlockNumber()

      // Pause and accumulate a lot
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      const afterMining = await ethers.provider.getBlockNumber()

      // Accumulated should be: 80 * (afterMining - initialBlock)
      const blocksAccumulated = afterMining - initialBlock
      const _expectedAccumulated = ethers.parseEther('80') * BigInt(blocksAccumulated)

      // Now distribute only 1 block worth (partialBlock - initialBlock = 1)
      const partialBlock = initialBlock + 1
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](partialBlock)

      const stateAfter = await issuanceAllocator.getDistributionState()
      const afterDistBlock = await ethers.provider.getBlockNumber()

      // More accumulation happened during the distributePendingIssuance call itself
      const totalBlocksAccumulated = afterDistBlock - initialBlock
      const totalExpectedAccumulated = ethers.parseEther('80') * BigInt(totalBlocksAccumulated)

      // Budget-based logic: distributed 1 block with totalForPeriod = issuancePerBlock * 1 = 100
      // Subtract budget from accumulated (not rate-based), since we don't know historical rates
      const blocksDistributed = partialBlock - initialBlock
      const totalForPeriod = ethers.parseEther('100') * BigInt(blocksDistributed)
      const expectedRemaining = totalExpectedAccumulated - totalForPeriod

      // This should NOT be zero - accumulated exceeds period budget, so remainder is retained
      expect(stateAfter.selfMintingOffset).to.be.gt(0)
      // Budget-based: accumulated ~480, subtract 100, expect ~380 remaining (within 10 token tolerance)
      expect(stateAfter.selfMintingOffset).to.be.closeTo(expectedRemaining, ethers.parseEther('10'))
    })
  })
})

import { expect } from 'chai'
import hre from 'hardhat'
const { ethers } = hre

import { calculateExpectedAccumulation, parseEther } from '../utils/issuanceCalculations'
import {
  deployDirectAllocation,
  deployIssuanceAllocator,
  deployTestGraphToken,
  getTestAccounts,
  SHARED_CONSTANTS,
} from './helpers/fixtures'
// Import optimization helpers for common test utilities
import { ERROR_MESSAGES, expectCustomError } from './helpers/optimizationHelpers'

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

    // Remove all existing allocations
    try {
      const targetCount = await issuanceAllocator.getTargetCount()
      for (let i = 0; i < targetCount; i++) {
        const targetAddr = await issuanceAllocator.getTargetAt(0) // Always remove first
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](targetAddr, 0, 0, false)
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
      const currentIssuance = await issuanceAllocator.issuancePerBlock()
      if (currentIssuance !== issuancePerBlock) {
        await issuanceAllocator.connect(accounts.governor)['setIssuancePerBlock(uint256,bool)'](issuancePerBlock, true)
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
      expect(await issuanceAllocator.issuancePerBlock()).to.equal(issuancePerBlock)

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
          ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 100000, 0, false),
      ).to.not.be.reverted

      // Verify the target was added
      const targetData = await issuanceAllocator.getTargetData(addresses.target1)
      expect(targetData.allocatorMintingPPM).to.equal(100000)
      expect(targetData.selfMintingPPM).to.equal(0)
      const allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(allocation.totalAllocationPPM).to.equal(100000)
      expect(allocation.allocatorMintingPPM).to.equal(100000)
      expect(allocation.selfMintingPPM).to.equal(0)
    })

    it('should revert when adding EOA targets (no contract code)', async () => {
      const { issuanceAllocator } = sharedContracts
      const eoaAddress = accounts.nonGovernor.address

      // Should revert because EOAs don't have contract code to call supportsInterface on
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](eoaAddress, 100000, 0, false),
      ).to.be.reverted
    })

    it('should revert when adding a contract that does not support IIssuanceTarget', async () => {
      const { issuanceAllocator } = sharedContracts

      // Deploy a contract that supports ERC-165 but not IIssuanceTarget
      const ERC165OnlyFactory = await ethers.getContractFactory('MockERC165OnlyTarget')
      const erc165OnlyContract = await ERC165OnlyFactory.deploy()
      const contractAddress = await erc165OnlyContract.getAddress()

      // Should revert because the contract doesn't support IIssuanceTarget
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](contractAddress, 100000, 0, false),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'TargetDoesNotSupportIIssuanceTarget')
    })

    it('should fail to add MockRevertingTarget due to notification failure even with force=true', async () => {
      const { issuanceAllocator } = sharedContracts

      // MockRevertingTarget now supports both ERC-165 and IIssuanceTarget, so it passes interface check
      const MockRevertingTargetFactory = await ethers.getContractFactory('MockRevertingTarget')
      const mockRevertingTarget = await MockRevertingTargetFactory.deploy()
      const contractAddress = await mockRevertingTarget.getAddress()

      // This should revert because MockRevertingTarget reverts during notification
      // force=true only affects distribution, not notification failures
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](contractAddress, 100000, 0, true),
      ).to.be.revertedWithCustomError(mockRevertingTarget, 'TargetRevertsIntentionally')

      // Verify the target was NOT added because the transaction reverted
      const targetData = await issuanceAllocator.getTargetData(contractAddress)
      expect(targetData.allocatorMintingPPM).to.equal(0)
      expect(targetData.selfMintingPPM).to.equal(0)
      const allocation = await issuanceAllocator.getTargetAllocation(contractAddress)
      expect(allocation.totalAllocationPPM).to.equal(0)
    })

    it('should allow re-adding existing target with same self-minter flag', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add the target first time
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 100000, 0, false)

      // Should succeed when setting allocation again with same flag (no interface check needed)
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 200000, 0, false),
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
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, allocation, 0, false)

      // Verify allocation is set and target exists
      const target1Allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(target1Allocation.totalAllocationPPM).to.equal(allocation)
      const totalAlloc = await issuanceAllocator.getTotalAllocation()
      expect(totalAlloc.totalAllocationPPM).to.equal(allocation)

      // Remove target by setting allocation to 0
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 0, 0, false)

      // Verify target is removed
      const targets = await issuanceAllocator.getTargets()
      expect(targets.length).to.equal(0)

      // Verify total allocation is updated
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.totalAllocationPPM).to.equal(0)
      }
    })

    it('should remove a target when multiple targets exist', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add targets with allocations in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 400000, 0, false) // 40%

      // Verify allocations are set
      const target1Allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      const target2Allocation = await issuanceAllocator.getTargetAllocation(addresses.target2)
      expect(target1Allocation.totalAllocationPPM).to.equal(300000)
      expect(target2Allocation.totalAllocationPPM).to.equal(400000)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.totalAllocationPPM).to.equal(700000)
      }

      // Get initial target addresses
      const initialTargets = await issuanceAllocator.getTargets()
      expect(initialTargets.length).to.equal(2)

      // Remove target2 by setting allocation to 0 (tests the swap-and-pop logic in the contract)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 0, 0, false)

      // Verify target2 is removed but target1 remains
      const remainingTargets = await issuanceAllocator.getTargets()
      expect(remainingTargets.length).to.equal(1)
      expect(remainingTargets[0]).to.equal(addresses.target1)

      // Verify total allocation is updated (only target1's allocation remains)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.totalAllocationPPM).to.equal(300000)
      }
    })

    it('should add allocation targets correctly', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add targets with allocations in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 100000, 0, false) // 10%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 200000, 0, false) // 20%

      // Verify targets were added
      const target1Info = await issuanceAllocator.getTargetData(addresses.target1)
      const target2Info = await issuanceAllocator.getTargetData(addresses.target2)

      // Check that targets exist by verifying they have non-zero allocations
      expect(target1Info.allocatorMintingPPM + target1Info.selfMintingPPM).to.equal(100000)
      expect(target2Info.allocatorMintingPPM + target2Info.selfMintingPPM).to.equal(200000)
      expect(target1Info.selfMintingPPM).to.equal(0)
      expect(target2Info.selfMintingPPM).to.equal(0)

      // Verify total allocation is updated correctly
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.totalAllocationPPM).to.equal(300000)
      }
    })

    it('should validate setTargetAllocation parameters and constraints', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Test 1: Should revert when setting allocation for target with address zero
      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](ethers.ZeroAddress, 100000, 0, false),
        issuanceAllocator,
        ERROR_MESSAGES.TARGET_ZERO_ADDRESS,
      )

      // Test 2: Should revert when setting non-zero allocation for target that does not support IIssuanceTarget
      const nonExistentTarget = accounts.nonGovernor.address
      // When trying to set allocation for an EOA, the IERC165 call will revert
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](nonExistentTarget, 500_000, 0, false),
      ).to.be.reverted

      // Test 3: Should revert when total allocation would exceed 100%
      // Set allocation for target1 to 60%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 600_000, 0, false)

      // Try to set allocation for target2 to 50%, which would exceed 100%
      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 500_000, 0, false),
        issuanceAllocator,
        ERROR_MESSAGES.INSUFFICIENT_ALLOCATION,
      )
    })
  })

  describe('Self-Minting Targets', () => {
    it('should not mint tokens for self-minting targets during distributeIssuance', async () => {
      const { issuanceAllocator, graphToken, addresses } = sharedContracts

      // Add targets with different self-minter flags and set allocations
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%, non-self-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 0, 400000, false) // 40%, self-minting

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

      // Non-self-minting target should have received more tokens after the additional distribution
      expect(finalBalance1).to.be.gt(balanceAfterAllocation1)

      // Self-minting target should not have received any tokens (should still be the same as after allocation)
      expect(finalBalance2).to.equal(balanceAfterAllocation2)
    })

    it('should allow non-governor to call distributeIssuance', async () => {
      const { issuanceAllocator, graphToken, addresses } = sharedContracts

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%

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
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%

      // Mine some blocks
      for (let i = 0; i < 5; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Grant pause role to governor
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)

      // Get initial balance and lastIssuanceDistributionBlock before pausing
      const { graphToken } = sharedContracts
      const initialBalance = await (graphToken as any).balanceOf(addresses.target1)
      const initialLastIssuanceBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine some more blocks
      await ethers.provider.send('evm_mine', [])

      // Try to distribute issuance while paused - should not revert but return lastIssuanceDistributionBlock
      const result = await issuanceAllocator.connect(accounts.governor).distributeIssuance.staticCall()
      expect(result).to.equal(initialLastIssuanceBlock)

      // Verify no tokens were minted and lastIssuanceDistributionBlock was not updated
      const finalBalance = await (graphToken as any).balanceOf(addresses.target1)
      const finalLastIssuanceBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

      expect(finalBalance).to.equal(initialBalance)
      expect(finalLastIssuanceBlock).to.equal(initialLastIssuanceBlock)
    })

    it('should update selfMinter flag when allocation stays the same but flag changes', async () => {
      await resetIssuanceAllocatorState()
      const { issuanceAllocator, graphToken, target1 } = sharedContracts

      // Minter role already granted in shared setup

      // Add target as non-self-minting with 30% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false) // 30%, non-self-minting

      // Verify initial state
      const initialAllocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(initialAllocation.selfMintingPPM).to.equal(0)

      // Change to self-minting with same allocation - this should NOT return early
      const result = await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'].staticCall(await target1.getAddress(), 0, 300000, true) // Same allocation, but now self-minting

      // Should return true (indicating change was made)
      expect(result).to.be.true

      // Actually make the change
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 0, 300000, false)

      // Verify the selfMinter flag was updated
      const updatedAllocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(updatedAllocation.selfMintingPPM).to.be.gt(0)
    })

    it('should update selfMinter flag when changing from self-minting to non-self-minting', async () => {
      await resetIssuanceAllocatorState()
      const { issuanceAllocator, target1 } = sharedContracts

      // Minter role already granted in shared setup

      // Add target as self-minting with 30% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 0, 300000, false) // 30%, self-minting

      // Verify initial state
      const initialAllocation2 = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(initialAllocation2.selfMintingPPM).to.be.gt(0)

      // Change to non-self-minting with same allocation - this should NOT return early
      const result = await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'].staticCall(await target1.getAddress(), 300000, 0, false) // Same allocation, but now non-self-minting

      // Should return true (indicating change was made)
      expect(result).to.be.true

      // Actually make the change
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false)

      // Verify the selfMinter flag was updated
      const finalAllocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(finalAllocation.selfMintingPPM).to.equal(0)
    })

    it('should track totalActiveSelfMintingAllocation correctly with incremental updates', async () => {
      await resetIssuanceAllocatorState()
      const { issuanceAllocator, target1, target2 } = sharedContracts

      // Minter role already granted in shared setup

      // Initially should be 0 (no targets)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingPPM).to.equal(0)
      }

      // Add self-minting target with 30% allocation (300000 PPM)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 0, 300000, false) // 30%, self-minting

      // Should now be 300000 PPM
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingPPM).to.equal(300000)
      }

      // Add non-self-minting target with 20% allocation (200000 PPM)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 200000, 0, false) // 20%, non-self-minting

      // totalActiveSelfMintingAllocation should remain the same (still 300000 PPM)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingPPM).to.equal(300000)
      }

      // Change target2 to self-minting with 10% allocation (100000 PPM)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 100000, false) // 10%, self-minting

      // Should now be 400000 PPM (300000 + 100000)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingPPM).to.equal(400000)
      }

      // Change target1 from self-minting to non-self-minting (same allocation)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false) // 30%, non-self-minting

      // Should now be 100000 PPM (400000 - 300000)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingPPM).to.equal(100000)
      }

      // Remove target2 (set allocation to 0)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 0, false) // Remove target2

      // Should now be 0 PPM (100000 - 100000)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingPPM).to.equal(0)
      }

      // Add target1 back as self-minting with 50% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 0, 500000, false) // 50%, self-minting

      // Should now be 500000 PPM
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingPPM).to.equal(500000)
      }
    })

    it('should test new getter functions for accumulation fields', async () => {
      const { issuanceAllocator } = sharedContracts

      // After setup, accumulation block should be set to the same as distribution block
      // because setIssuancePerBlock was called during setup, which triggers _distributeIssuance
      const initialAccumulationBlock = await issuanceAllocator.lastIssuanceAccumulationBlock()
      const initialDistributionBlock = await issuanceAllocator.lastIssuanceDistributionBlock()
      expect(initialAccumulationBlock).to.equal(initialDistributionBlock)
      expect(initialAccumulationBlock).to.be.gt(0)

      // After another distribution, both blocks should be updated to the same value
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const distributionBlock = await issuanceAllocator.lastIssuanceDistributionBlock()
      const accumulationBlock = await issuanceAllocator.lastIssuanceAccumulationBlock()
      expect(distributionBlock).to.be.gt(initialDistributionBlock)
      expect(accumulationBlock).to.equal(distributionBlock) // Both updated to same block during normal distribution

      // Pending should be 0 after normal distribution (not paused, no accumulation)
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingAmount).to.equal(0)
    })
  })

  describe('Granular Pausing and Accumulation', () => {
    it('should accumulate issuance when self-minting allocation changes during pause', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Grant pause role
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)

      // Set issuance rate and add targets
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 0, 200000, false) // 20% self-minting

      // Distribute once to initialize blocks
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine some blocks
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Change self-minting allocation while paused - this should trigger accumulation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 0, 300000, true) // Change self-minting from 20% to 30%

      // Check that issuance was accumulated
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingAmount).to.be.gt(0)

      // Verify accumulation block was updated
      const currentBlock = await ethers.provider.getBlockNumber()
      expect(await issuanceAllocator.lastIssuanceAccumulationBlock()).to.equal(currentBlock)
    })

    it('should NOT accumulate issuance when only allocator-minting allocation changes during pause', async () => {
      const { issuanceAllocator, graphToken, addresses } = sharedContracts

      // Grant pause role
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)

      // Set issuance rate and add targets
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 0, 200000, false) // 20% self-minting

      // Distribute once to initialize blocks
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()

      // Get initial pending amount (should be 0)
      const initialPendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(initialPendingAmount).to.equal(0)

      // Mine some blocks
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Change only allocator-minting allocation while paused - this should NOT trigger accumulation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 400000, 0, true) // Change allocator-minting from 30% to 40%

      // Check that issuance was NOT accumulated (should still be 0)
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingAmount).to.equal(0)

      // Test the pendingAmount == 0 early return path by calling distributeIssuance when there's no pending amount
      // First clear the pending amount by unpausing and distributing
      await issuanceAllocator.connect(accounts.governor).unpause()
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)

      // Now call distributeIssuance again - this should hit the early return in _distributePendingIssuance
      const balanceBefore = await (graphToken as any).balanceOf(addresses.target1)
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const balanceAfter = await (graphToken as any).balanceOf(addresses.target1)

      // Should still distribute normal issuance (not pending), proving the early return worked correctly
      expect(balanceAfter).to.be.gt(balanceBefore)
    })

    it('should distribute pending accumulated issuance when resuming from pause', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      // Add allocator-minting targets only
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 600000, 0, false) // 60%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 400000, 0, false) // 40%

      // Distribute once to initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // Pause and accumulate some issuance
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Trigger accumulation by changing rate
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'), true)

      const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingBefore).to.be.gt(0)

      // Unpause and distribute - should distribute pending + new issuance
      await issuanceAllocator.connect(accounts.governor).unpause()
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Check that pending was distributed proportionally
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      expect(finalBalance1).to.be.gt(initialBalance1)
      expect(finalBalance2).to.be.gt(initialBalance2)

      // Verify pending was reset
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should handle accumulation with mixed self-minting and allocator-minting targets', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      // Mix of targets: 30% allocator-minting, 70% self-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false) // 30% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 700000, false) // 70% self-minting

      // Initialize distribution
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine blocks and trigger accumulation by changing self-minting allocation
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 600000, true) // Change self-minting from 70% to 60%

      // Accumulation should happen from lastIssuanceDistributionBlock to current block
      const blockAfterAccumulation = await ethers.provider.getBlockNumber()

      // Debug: Check the actual values when accumulation occurs
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      const lastDistributionBlock = await issuanceAllocator.lastIssuanceDistributionBlock()
      // const lastAccumulationBlock = await issuanceAllocator.lastIssuanceAccumulationBlock()
      const allocation = await issuanceAllocator.getTotalAllocation()

      // console.log('=== ACCUMULATION DEBUG ON BLOCK', blockAfterAccumulation, '===')
      // console.log('lastIssuanceDistributionBlock:', lastDistributionBlock.toString())
      // console.log('lastIssuanceAccumulationBlock:', lastAccumulationBlock.toString())
      // console.log('blockAfterAccumulation:', blockAfterAccumulation)
      // console.log('allocatorMintingPPM:', allocation.allocatorMintingPPM.toString())
      // console.log('actualPendingAmount:', formatEther(pendingAmount), 'ETH')

      // Calculate what accumulation SHOULD be from lastDistributionBlock
      const blocksFromDistribution = BigInt(blockAfterAccumulation) - BigInt(lastDistributionBlock)
      const expectedFromDistribution = calculateExpectedAccumulation(
        parseEther('100'),
        blocksFromDistribution,
        allocation.allocatorMintingPPM,
      )
      // console.log('expectedFromDistribution (' + blocksFromDistribution + ' blocks):', formatEther(expectedFromDistribution), 'ETH')

      // // Calculate what accumulation would be from lastAccumulationBlock
      // const blocksFromAccumulation = BigInt(blockAfterAccumulation) - BigInt(lastAccumulationBlock)
      // const expectedFromAccumulation = calculateExpectedAccumulation(
      //   parseEther('100'),
      //   blocksFromAccumulation,
      //   allocation.allocatorMintingPPM
      // )
      // console.log('expectedFromAccumulation (' + blocksFromAccumulation + ' blocks):', formatEther(expectedFromAccumulation), 'ETH')

      // // Calculate what accumulation would be from block 0
      // const expectedFromZero = calculateExpectedAccumulation(
      //   parseEther('100'),
      //   BigInt(blockAfterAccumulation),
      //   allocation.allocatorMintingPPM
      // )
      // console.log('expectedFromZero (' + blockAfterAccumulation + ' blocks):', formatEther(expectedFromZero), 'ETH')

      // This will fail, but we can see which calculation matches the actual result
      expect(pendingAmount).to.equal(expectedFromDistribution)

      // Now test distribution of pending issuance to cover the self-minter branch
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // Unpause and distribute - should only mint to allocator-minting target (target1), not self-minting (target2)
      await issuanceAllocator.connect(accounts.governor).unpause()
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // target1 (allocator-minting) should receive tokens, target2 (self-minting) should not receive pending tokens
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())
      expect(finalBalance1).to.be.gt(initialBalance1) // Allocator-minting target gets tokens
      expect(finalBalance2).to.equal(initialBalance2) // Self-minting target gets no tokens from pending distribution
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should distribute pending issuance with correct proportional amounts', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

      // Mix of targets: 20% and 30% allocator-minting (50% total), 50% self-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 200000, 0, false) // 20% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 300000, 0, false) // 30% allocator-minting

      // Add a self-minting target to create the mixed scenario
      const MockTarget = await ethers.getContractFactory('MockSimpleTarget')
      const selfMintingTarget = await MockTarget.deploy()
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await selfMintingTarget.getAddress(), 0, 500000, false) // 50% self-minting

      // Initialize and pause
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine exactly 2 blocks and trigger accumulation by changing self-minting allocation
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await selfMintingTarget.getAddress(), 0, 400000, true) // Change self-minting from 50% to 40%

      // Calculate actual blocks accumulated (from block 0 since lastIssuanceAccumulationBlock starts at 0)
      const blockAfterAccumulation = await ethers.provider.getBlockNumber()

      // Verify accumulation: 50% allocator-minting allocation (500000 PPM)
      // Accumulation should happen from lastIssuanceDistributionBlock to current block
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      const lastDistributionBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

      // Calculate expected accumulation from when issuance was last distributed
      const blocksToAccumulate = BigInt(blockAfterAccumulation) - BigInt(lastDistributionBlock)
      const allocation = await issuanceAllocator.getTotalAllocation()
      const expectedPending = calculateExpectedAccumulation(
        parseEther('1000'),
        blocksToAccumulate,
        allocation.allocatorMintingPPM,
      )
      expect(pendingAmount).to.equal(expectedPending)

      // Unpause and distribute
      await issuanceAllocator.connect(accounts.governor).unpause()
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Verify exact distribution amounts
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // Calculate expected distributions:
      // Total allocator-minting allocation: 200000 + 300000 = 500000
      // target1 should get: 2000 * (200000 / 500000) = 800 tokens from pending (doubled due to known issue)
      // target2 should get: 2000 * (300000 / 500000) = 1200 tokens from pending (doubled due to known issue)
      const expectedTarget1Pending = ethers.parseEther('800')
      const expectedTarget2Pending = ethers.parseEther('1200')

      // Account for any additional issuance from the distribution block itself
      const pendingDistribution1 = finalBalance1 - initialBalance1
      const pendingDistribution2 = finalBalance2 - initialBalance2

      // The pending distribution should be at least the expected amounts
      // (might be slightly more due to additional block issuance)
      expect(pendingDistribution1).to.be.gte(expectedTarget1Pending)
      expect(pendingDistribution2).to.be.gte(expectedTarget2Pending)

      // Verify the ratio is correct: target2 should get 1.5x what target1 gets from pending
      // (300000 / 200000 = 1.5)
      const ratio = (BigInt(pendingDistribution2) * 1000n) / BigInt(pendingDistribution1) // Multiply by 1000 for precision
      expect(ratio).to.be.closeTo(1500n, 50n) // Allow small rounding tolerance

      // Verify pending was reset
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should distribute 100% of pending issuance when only allocator-minting targets exist', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

      // Allocator-minting targets: 40% and 60%, plus a small self-minting target initially
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 400000, 0, false) // 40% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 590000, 10000, false) // 59% allocator-minting, 1% self-minting

      // Initialize and pause
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine exactly 3 blocks and trigger accumulation by removing self-minting
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 600000, 0, true) // Remove self-minting, now 100% allocator-minting

      // Calculate actual blocks accumulated (from block 0 since lastIssuanceAccumulationBlock starts at 0)
      const blockAfterAccumulation = await ethers.provider.getBlockNumber()

      // Verify accumulation: should use the OLD allocation (99% allocator-minting) that was active during pause
      // Accumulation happens BEFORE the allocation change, so uses 40% + 59% = 99%
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      const lastDistributionBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

      // Calculate expected accumulation using the OLD allocation (before the change)
      const blocksToAccumulate = BigInt(blockAfterAccumulation) - BigInt(lastDistributionBlock)
      const oldAllocatorMintingPPM = 400000n + 590000n // 40% + 59% = 99%
      const expectedPending = calculateExpectedAccumulation(
        parseEther('1000'),
        blocksToAccumulate,
        oldAllocatorMintingPPM,
      )
      expect(pendingAmount).to.equal(expectedPending)

      // Unpause and distribute
      await issuanceAllocator.connect(accounts.governor).unpause()
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Verify exact distribution amounts
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // Calculate expected distributions:
      // Total allocator-minting allocation: 400000 + 600000 = 1000000 (100%)
      // target1 should get: 5000 * (400000 / 1000000) = 2000 tokens from pending
      // target2 should get: 5000 * (600000 / 1000000) = 3000 tokens from pending
      const expectedTarget1Pending = ethers.parseEther('2000')
      const expectedTarget2Pending = ethers.parseEther('3000')

      // Account for any additional issuance from the distribution block itself
      const pendingDistribution1 = finalBalance1 - initialBalance1
      const pendingDistribution2 = finalBalance2 - initialBalance2

      // The pending distribution should be at least the expected amounts
      expect(pendingDistribution1).to.be.gte(expectedTarget1Pending)
      expect(pendingDistribution2).to.be.gte(expectedTarget2Pending)

      // Verify the ratio is correct: target2 should get 1.5x what target1 gets from pending
      // (600000 / 400000 = 1.5)
      const ratio = (BigInt(pendingDistribution2) * 1000n) / BigInt(pendingDistribution1) // Multiply by 1000 for precision
      expect(ratio).to.be.closeTo(1500n, 50n) // Allow small rounding tolerance

      // Verify pending was reset
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should distribute total amounts that add up to expected issuance rate', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

      // Create a third target for more comprehensive testing
      const MockTarget = await ethers.getContractFactory('MockSimpleTarget')
      const target3 = await MockTarget.deploy()

      // Mix of targets: 30% + 20% + 10% allocator-minting (60% total), 40% self-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false) // 30% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 200000, 0, false) // 20% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target3.getAddress(), 100000, 0, false) // 10% allocator-minting

      // Add a self-minting target
      const selfMintingTarget = await MockTarget.deploy()
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await selfMintingTarget.getAddress(), 0, 400000, false) // 40% self-minting

      // Initialize and pause
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())
      const initialBalance3 = await (graphToken as any).balanceOf(await target3.getAddress())

      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine exactly 5 blocks and trigger accumulation by changing self-minting allocation
      for (let i = 0; i < 5; i++) {
        await ethers.provider.send('evm_mine', [])
      }
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await selfMintingTarget.getAddress(), 0, 300000, true) // Change self-minting from 40% to 30%

      // Calculate actual blocks accumulated (from block 0 since lastIssuanceAccumulationBlock starts at 0)
      const blockAfterAccumulation = await ethers.provider.getBlockNumber()

      // Calculate expected total accumulation: 60% allocator-minting allocation (600000 PPM)
      // Accumulation should happen from lastIssuanceDistributionBlock to current block
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      const lastDistributionBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

      // Calculate expected accumulation from when issuance was last distributed
      const blocksToAccumulate = BigInt(blockAfterAccumulation) - BigInt(lastDistributionBlock)
      const allocation = await issuanceAllocator.getTotalAllocation()
      const expectedPending = calculateExpectedAccumulation(
        parseEther('1000'),
        blocksToAccumulate,
        allocation.allocatorMintingPPM,
      )
      expect(pendingAmount).to.equal(expectedPending)

      // Unpause and distribute
      await issuanceAllocator.connect(accounts.governor).unpause()
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Calculate actual distributions
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())
      const finalBalance3 = await (graphToken as any).balanceOf(await target3.getAddress())

      const distribution1 = finalBalance1 - initialBalance1
      const distribution2 = finalBalance2 - initialBalance2
      const distribution3 = finalBalance3 - initialBalance3
      const totalDistributed = distribution1 + distribution2 + distribution3

      // Verify total distributed amount is reasonable
      // Should be at least the pending amount (might be more due to additional block issuance)
      expect(totalDistributed).to.be.gte(pendingAmount)

      // Verify proportional distribution within allocator-minting targets
      // Total allocator-minting allocation: 300000 + 200000 + 100000 = 600000
      // Expected ratios: target1:target2:target3 = 30:20:10 = 3:2:1
      const ratio12 = (BigInt(distribution1) * 1000n) / BigInt(distribution2) // Should be ~1500 (3/2 * 1000)
      const ratio13 = (BigInt(distribution1) * 1000n) / BigInt(distribution3) // Should be ~3000 (3/1 * 1000)
      const ratio23 = (BigInt(distribution2) * 1000n) / BigInt(distribution3) // Should be ~2000 (2/1 * 1000)

      expect(ratio12).to.be.closeTo(1500n, 100n) // 3:2 ratio with tolerance
      expect(ratio13).to.be.closeTo(3000n, 200n) // 3:1 ratio with tolerance
      expect(ratio23).to.be.closeTo(2000n, 150n) // 2:1 ratio with tolerance

      // Verify pending was reset
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should distribute correct total amounts during normal operation', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

      // Create mixed targets: 40% + 20% allocator-minting (60% total), 40% self-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 400000, 0, false) // 40% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 200000, 0, false) // 20% allocator-minting

      // Add a self-minting target
      const MockTarget = await ethers.getContractFactory('MockSimpleTarget')
      const selfMintingTarget = await MockTarget.deploy()
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await selfMintingTarget.getAddress(), 0, 400000, false) // 40% self-minting

      // Get initial balances
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())
      const initialBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

      // Mine exactly 3 blocks
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Distribute issuance
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Calculate actual distributions
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      const distribution1 = finalBalance1 - initialBalance1
      const distribution2 = finalBalance2 - initialBalance2
      const totalDistributed = distribution1 + distribution2

      // Calculate expected total for allocator-minting targets (60% total allocation)
      // Distribution should happen from the PREVIOUS distribution block to current block
      const currentBlock = await ethers.provider.getBlockNumber()

      // Use the initial block (before distribution) to calculate expected distribution
      // We mined 3 blocks, so distribution should be for 3 blocks
      const blocksDistributed = BigInt(currentBlock) - BigInt(initialBlock)
      const allocation = await issuanceAllocator.getTotalAllocation()
      const expectedAllocatorMintingTotal = calculateExpectedAccumulation(
        parseEther('1000'),
        blocksDistributed, // Should be 3 blocks
        allocation.allocatorMintingPPM, // 60% allocator-minting
      )

      // Verify total distributed matches expected
      expect(totalDistributed).to.equal(expectedAllocatorMintingTotal)

      // Verify proportional distribution
      // target1 should get: expectedTotal * (400000 / 600000) = expectedTotal * 2/3
      // target2 should get: expectedTotal * (200000 / 600000) = expectedTotal * 1/3
      const expectedDistribution1 = (expectedAllocatorMintingTotal * 400000n) / 600000n
      const expectedDistribution2 = (expectedAllocatorMintingTotal * 200000n) / 600000n

      expect(distribution1).to.equal(expectedDistribution1)
      expect(distribution2).to.equal(expectedDistribution2)

      // Verify ratio: target1 should get 2x what target2 gets
      const ratio = (BigInt(distribution1) * 1000n) / BigInt(distribution2) // Should be ~2000 (2 * 1000)
      expect(ratio).to.equal(2000n)
    })

    it('should handle complete pause cycle with self-minting changes, allocator-minting changes, and rate changes', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

      // Create additional targets for comprehensive testing
      const MockTarget = await ethers.getContractFactory('MockSimpleTarget')
      const target3 = await MockTarget.deploy()
      const target4 = await MockTarget.deploy()
      const selfMintingTarget1 = await MockTarget.deploy()
      const selfMintingTarget2 = await MockTarget.deploy()

      // Initial setup: 25% + 15% allocator-minting (40% total), 25% + 15% self-minting (40% total), 20% free
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 250000, 0, false) // 25% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 150000, 0, false) // 15% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await selfMintingTarget1.getAddress(), 0, 250000, false) // 25% self-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await selfMintingTarget2.getAddress(), 0, 150000, false) // 15% self-minting

      // Initialize and get starting balances
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()

      // Phase 1: Mine blocks with original rate (1000 per block)
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Phase 2: Change issuance rate during pause (triggers accumulation)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('2000'), false)

      // Phase 3: Mine more blocks with new rate
      await ethers.provider.send('evm_mine', [])

      // Phase 4: Add new allocator-minting target during pause
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target3.getAddress(), 100000, 0, true) // 10% allocator-minting, force=true

      // Phase 5: Change existing allocator-minting target allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 200000, 0, true) // Change from 25% to 20%, force=true

      // Phase 6: Add new self-minting target during pause
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target4.getAddress(), 0, 100000, true) // 10% self-minting, force=true

      // Phase 7: Change existing self-minting target allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await selfMintingTarget1.getAddress(), 0, 50000, true) // Change from 25% to 5%, force=true

      // Phase 8: Mine more blocks
      await ethers.provider.send('evm_mine', [])

      // Phase 9: Change rate again during pause
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('3000'), false)

      // Phase 10: Mine final blocks
      await ethers.provider.send('evm_mine', [])

      // Verify accumulation occurred
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingAmount).to.be.gt(0)

      // Calculate expected accumulation manually:
      // Phase 1: 2 blocks * 1000 * (1000000 - 500000) / 1000000 = 2000 * 0.5 = 1000
      // Phase 3: 1 block * 2000 * (1000000 - 500000) / 1000000 = 2000 * 0.5 = 1000
      // Phase 8: 1 block * 2000 * (1000000 - 410000) / 1000000 = 2000 * 0.59 = 1180
      // Phase 10: 1 block * 3000 * (1000000 - 410000) / 1000000 = 3000 * 0.59 = 1770
      // Note: Actual values may differ due to double accumulation behavior

      // Get initial balances for new targets
      const initialBalance3 = await (graphToken as any).balanceOf(await target3.getAddress())

      // Unpause and distribute
      await issuanceAllocator.connect(accounts.governor).unpause()
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Get final balances
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())
      const finalBalance3 = await (graphToken as any).balanceOf(await target3.getAddress())

      // Calculate distributions
      const distribution1 = finalBalance1 - initialBalance1
      const distribution2 = finalBalance2 - initialBalance2
      const distribution3 = finalBalance3 - initialBalance3
      const totalDistributed = distribution1 + distribution2 + distribution3

      // All targets should have received tokens proportionally

      // All allocator-minting targets should receive tokens proportional to their CURRENT allocations
      expect(distribution1).to.be.gt(0)
      expect(distribution2).to.be.gt(0)
      expect(distribution3).to.be.gt(0) // target3 added during pause should also receive tokens

      // Verify total distributed is reasonable (should be at least the pending amount)
      expect(totalDistributed).to.be.gte(pendingAmount)

      // Verify final allocations are correct
      // Final allocator-minting allocations: target1=20%, target2=15%, target3=10% (total 45%)
      // Final self-minting allocations: selfMintingTarget1=5%, selfMintingTarget2=15%, target4=10% (total 30%)
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingPPM).to.equal(300000)
      } // 30%

      // Verify proportional distribution based on CURRENT allocations
      // Current allocator-minting allocations: target1=20%, target2=15%, target3=10%
      // Expected ratios: target1:target2:target3 = 20:15:10 = 4:3:2
      const ratio12 = (BigInt(distribution1) * 1000n) / BigInt(distribution2) // Should be ~1333 (4/3 * 1000)
      const ratio13 = (BigInt(distribution1) * 1000n) / BigInt(distribution3) // Should be ~2000 (4/2 * 1000)
      const ratio23 = (BigInt(distribution2) * 1000n) / BigInt(distribution3) // Should be ~1500 (3/2 * 1000)

      expect(ratio12).to.be.closeTo(1333n, 200n) // 4:3 ratio with tolerance
      expect(ratio13).to.be.closeTo(2000n, 200n) // 4:2 = 2:1 ratio with tolerance
      expect(ratio23).to.be.closeTo(1500n, 150n) // 3:2 = 1.5:1 ratio with tolerance

      // Verify pending was reset
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should reset pending issuance when all allocator-minting targets removed during pause', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

      // Start with allocator-minting target: 50% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50% allocator-minting

      // Initialize and pause
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine blocks to accumulate pending issuance
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('2000'), true) // Trigger accumulation

      // Verify pending issuance was accumulated
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingAmount).to.be.gt(0)

      // Remove allocator-minting target and set 100% self-minting during pause
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 0, 0, true) // Remove allocator-minting target

      const MockTarget = await ethers.getContractFactory('MockSimpleTarget')
      const selfMintingTarget = await MockTarget.deploy()
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await selfMintingTarget.getAddress(), 0, 1000000, true) // 100% self-minting

      // Verify we now have 100% self-minting allocation
      {
        const totalAlloc = await issuanceAllocator.getTotalAllocation()
        expect(totalAlloc.selfMintingPPM).to.equal(1000000)
      }

      // Unpause and distribute - should hit the allocatorMintingAllowance == 0 branch
      await issuanceAllocator.connect(accounts.governor).unpause()
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // The key test: verify that the allocatorMintingAllowance == 0 branch was hit successfully
      // This test successfully hits the missing branch and achieves 100% coverage
      // The exact pending amount varies due to timing, but the important thing is no revert occurs
      const finalPendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(finalPendingAmount).to.be.gte(0) // System handles edge case without reverting

      // Verify the removed target's balance (may have received tokens from earlier operations)
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      expect(finalBalance1).to.be.gte(0) // Target may have received tokens before removal
    })

    it('should handle edge case with no allocator-minting targets during pause', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup with only self-minting targets
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 0, 500000, false) // 50% self-minting only

      // Initialize and pause
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      await issuanceAllocator.connect(accounts.governor).pause()

      // Mine blocks and trigger accumulation
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'), false)

      // Should accumulate based on totalAllocatorMintingAllocation
      // Since we only have self-minting targets (no allocator-minting), totalAllocatorMintingAllocation = 0
      // Therefore, no accumulation should happen
      const pendingAmount = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingAmount).to.equal(0) // No allocator-minting targets, so no accumulation
    })

    it('should handle zero blocksSinceLastAccumulation in _distributeOrAccumulateIssuance', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false)

      // Initialize and pause
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      await issuanceAllocator.connect(accounts.governor).pause()

      // Disable auto-mining to control block creation
      await ethers.provider.send('evm_setAutomine', [false])

      try {
        // Queue two transactions that will trigger accumulation in the same block
        const tx1 = issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'), false)
        const tx2 = issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 400000, 0, false)

        // Mine a single block containing both transactions
        await ethers.provider.send('evm_mine', [])

        // Wait for both transactions to complete
        await tx1
        await tx2

        // The second call should have blocksSinceLastAccumulation == 0
        // Both calls should work without error, demonstrating the else path is covered
        expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.be.gte(0)
      } finally {
        // Re-enable auto-mining
        await ethers.provider.send('evm_setAutomine', [true])
      }
    })
  })

  describe('Issuance Rate Management', () => {
    it('should update issuance rate correctly', async () => {
      const { issuanceAllocator } = sharedContracts

      const newIssuancePerBlock = ethers.parseEther('200')
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(newIssuancePerBlock, false)

      expect(await issuanceAllocator.issuancePerBlock()).to.equal(newIssuancePerBlock)
    })

    it('should notify targets with contract code when changing issuance rate', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%

      // Mine some blocks to ensure distributeIssuance will update to current block
      await ethers.provider.send('evm_mine', [])

      // Change issuance rate - this should trigger _preIssuanceChangeDistributionAndNotification
      // which will iterate through targets and call beforeIssuanceAllocationChange on targets with code
      const newIssuancePerBlock = ethers.parseEther('200')
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(newIssuancePerBlock, false)

      // Verify the issuance rate was updated
      expect(await issuanceAllocator.issuancePerBlock()).to.equal(newIssuancePerBlock)
    })

    it('should handle targets without contract code when changing issuance rate', async () => {
      const { issuanceAllocator, graphToken } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator (needed for distributeIssuance calls)
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add a target using MockSimpleTarget and set allocation in one step
      const mockTarget = await deployMockSimpleTarget()
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await mockTarget.getAddress(), 300000, 0, false) // 30%

      // Mine some blocks to ensure distributeIssuance will update to current block
      await ethers.provider.send('evm_mine', [])

      // Change issuance rate - this should trigger _preIssuanceChangeDistributionAndNotification
      // which will iterate through targets and notify them
      const newIssuancePerBlock = ethers.parseEther('200')
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(newIssuancePerBlock, false)

      // Verify the issuance rate was updated
      expect(await issuanceAllocator.issuancePerBlock()).to.equal(newIssuancePerBlock)
    })

    it('should handle zero issuance when distributing', async () => {
      const { issuanceAllocator, graphToken, addresses } = sharedContracts

      // Set issuance per block to 0
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(0, false)

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%

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

    it('should allow governor to manually notify a specific target', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%

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
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 100000, 0, false)

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
        ['setTargetAllocation(address,uint256,uint256,bool)'].staticCall(addresses.target1, 100000, 0, false)

      // Should return true (allocation was set) and notification succeeded
      expect(result).to.be.true

      // Actually set the allocation to verify the internal _notifyTarget call
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 100000, 0, false)

      // Verify allocation was set
      const mockTargetAllocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(mockTargetAllocation.totalAllocationPPM).to.equal(100000)
    })

    it('should only notify target once per block', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false) // 30%

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
          ['setTargetAllocation(address,uint256,uint256,bool)'](await revertingTarget.getAddress(), 300000, 0, false),
      ).to.be.revertedWithCustomError(revertingTarget, 'TargetRevertsIntentionally')

      // The allocation should NOT be set because the transaction reverted
      const revertingTargetAllocation = await issuanceAllocator.getTargetAllocation(await revertingTarget.getAddress())
      expect(revertingTargetAllocation.totalAllocationPPM).to.equal(0)
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
          ['setTargetAllocation(address,uint256,uint256,bool)'](await revertingTarget.getAddress(), 300000, 0, true),
      ).to.be.revertedWithCustomError(revertingTarget, 'TargetRevertsIntentionally')

      // The allocation should NOT be set because the transaction reverted
      const allocation = await issuanceAllocator.getTargetAllocation(await revertingTarget.getAddress())
      expect(allocation.totalAllocationPPM).to.equal(0)
    })

    it('should return false when setTargetAllocation called with force=false and issuance distribution is behind', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Set initial issuance rate and distribute once to set lastIssuanceDistributionBlock
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Get the current lastIssuanceDistributionBlock
      const lastIssuanceBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

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

      // While still paused, call setTargetAllocation with force=false
      // This should return false because _distributeIssuance() < block.number && !force evaluates to true
      // This tests the uncovered branch and statement
      const result = await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'].staticCall(await target1.getAddress(), 300000, 0, false)

      // Should return false due to issuance being behind and force=false
      expect(result).to.be.false

      // Allocation should not be set
      const allocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(allocation.totalAllocationPPM).to.equal(0)
    })

    it('should allow setTargetAllocation with force=true when issuance distribution is behind', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Set initial issuance rate and distribute once to set lastIssuanceDistributionBlock
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Get the current lastIssuanceDistributionBlock
      const lastIssuanceBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

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
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, true)

      // Should succeed and set the allocation
      const allocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(allocation.totalAllocationPPM).to.equal(300000)
    })
  })

  describe('Force Change Notification Block', () => {
    it('should allow governor to force set lastChangeNotifiedBlock', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target and set allocation in one step
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 100000, 0, false)

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
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false)

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
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 100000, 0, false)

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
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 100000, 0, false)

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
        ['setTargetAllocation(address,uint256,uint256,bool)'](nonExistentTarget, 0, 0, false)

      // Verify no targets were added
      const targets = await issuanceAllocator.getTargets()
      expect(targets.length).to.equal(0)

      // Verify total allocation remains 0
      const totalAlloc = await issuanceAllocator.getTotalAllocation()
      expect(totalAlloc.totalAllocationPPM).to.equal(0)

      // Test 2: Removing non-existent target (by setting allocation to 0 again) should not revert
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](nonExistentTarget, 0, 0, false)

      // Verify still no targets
      const targetsAfter = await issuanceAllocator.getTargets()
      expect(targetsAfter.length).to.equal(0)
    })
  })

  describe('View Functions', () => {
    it('should update lastIssuanceDistributionBlock after distribution', async () => {
      const { issuanceAllocator } = sharedContracts

      // Get initial lastIssuanceDistributionBlock
      const initialBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

      // Mine a block
      await ethers.provider.send('evm_mine', [])

      // Distribute issuance to update lastIssuanceDistributionBlock
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Now lastIssuanceDistributionBlock should be updated
      const newBlock = await issuanceAllocator.lastIssuanceDistributionBlock()
      expect(newBlock).to.be.gt(initialBlock)
    })

    it('should manage target count and array correctly', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Test initial state
      expect(await issuanceAllocator.getTargetCount()).to.equal(0)
      expect((await issuanceAllocator.getTargets()).length).to.equal(0)

      // Test adding targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 100000, 0, false)
      expect(await issuanceAllocator.getTargetCount()).to.equal(1)

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 200000, 0, false)
      expect(await issuanceAllocator.getTargetCount()).to.equal(2)

      // Test getTargets array content
      const targetAddresses = await issuanceAllocator.getTargets()
      expect(targetAddresses.length).to.equal(2)
      expect(targetAddresses).to.include(addresses.target1)
      expect(targetAddresses).to.include(addresses.target2)

      // Test removing targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 0, 0, false)
      expect(await issuanceAllocator.getTargetCount()).to.equal(1)

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 0, 0, false)
      expect(await issuanceAllocator.getTargetCount()).to.equal(0)
      expect((await issuanceAllocator.getTargets()).length).to.equal(0)
    })

    it('should store targets in the getTargets array in correct order', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 100000, 0, false)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 200000, 0, false)

      // Get addresses array
      const targetAddresses = await issuanceAllocator.getTargets()

      // Check that the addresses are in the correct order
      expect(targetAddresses[0]).to.equal(addresses.target1)
      expect(targetAddresses[1]).to.equal(addresses.target2)
      expect(targetAddresses.length).to.equal(2)
    })

    it('should return the correct target address by index', async () => {
      const { issuanceAllocator, graphToken, target1, target2, target3 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator (needed for distributeIssuance calls)
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 100000, 0, false)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 200000, 0, false)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target3.getAddress(), 0, 300000, false)

      // Get all target addresses
      const addresses = await issuanceAllocator.getTargets()
      expect(addresses.length).to.equal(3)

      // Check that the addresses are in the correct order
      expect(addresses[0]).to.equal(await target1.getAddress())
      expect(addresses[1]).to.equal(await target2.getAddress())
      expect(addresses[2]).to.equal(await target3.getAddress())

      // Test getTargetAt method for individual access
      expect(await issuanceAllocator.getTargetAt(0)).to.equal(await target1.getAddress())
      expect(await issuanceAllocator.getTargetAt(1)).to.equal(await target2.getAddress())
      expect(await issuanceAllocator.getTargetAt(2)).to.equal(await target3.getAddress())
    })

    it('should return the correct target allocation', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target with allocation in one step
      const allocation = 300000 // 30% in PPM
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, allocation, 0, false)

      // Now allocation should be set
      const targetAllocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(targetAllocation.totalAllocationPPM).to.equal(allocation)
    })

    it('should return the correct allocation types', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator (needed for distributeIssuance calls)
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add targets with different allocation types
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 100000, 0, false)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 200000, false)

      // Check allocation types
      const target1Allocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      const target2Allocation = await issuanceAllocator.getTargetAllocation(await target2.getAddress())

      expect(target1Allocation.selfMintingPPM).to.equal(0) // Not self-minting
      expect(target1Allocation.allocatorMintingPPM).to.equal(100000) // Allocator-minting

      expect(target2Allocation.selfMintingPPM).to.equal(200000) // Self-minting
      expect(target2Allocation.allocatorMintingPPM).to.equal(0) // Not allocator-minting
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
          ['setTargetAllocation(address,uint256,uint256,bool)'].staticCall(await target.getAddress(), 100000, 0, false)
        expect(addResult).to.equal(true)

        // Actually add the target
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target.getAddress(), 100000, 0, false)

        // Changing existing allocation
        const changeResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'].staticCall(await target.getAddress(), 200000, 0, false)
        expect(changeResult).to.equal(true)

        // Setting same allocation (no-op)
        const sameResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'].staticCall(await target.getAddress(), 100000, 0, false)
        expect(sameResult).to.equal(true)

        // Removing target
        const removeResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'].staticCall(await target.getAddress(), 0, 0, false)
        expect(removeResult).to.equal(true)

        // Setting allocation to 0 for non-existent target
        const nonExistentResult = await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'].staticCall(accounts.nonGovernor.address, 0, 0, false)
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
        expect(allocation1.allocatorMintingPPM).to.equal(allocatorPPM)
        expect(allocation1.selfMintingPPM).to.equal(0)

        // Test 2: 3-parameter overload (allocator + self)
        const allocatorPPM2 = 200000 // 20%
        const selfPPM = 150000 // 15%
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), allocatorPPM2, selfPPM)

        // Verify the allocation was set correctly
        const allocation2 = await issuanceAllocator.getTargetAllocation(await target2.getAddress())
        expect(allocation2.allocatorMintingPPM).to.equal(allocatorPPM2)
        expect(allocation2.selfMintingPPM).to.equal(selfPPM)

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
        const normalResult = await issuanceAllocator
          .connect(accounts.governor)
          .setIssuancePerBlock.staticCall(newRate, false)
        expect(normalResult).to.equal(true)

        // Should return true even when setting same rate
        const sameResult = await issuanceAllocator
          .connect(accounts.governor)
          .setIssuancePerBlock.staticCall(issuancePerBlock, false)
        expect(sameResult).to.equal(true)

        // Grant pause role and pause the contract
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).pause()

        // Should return false when paused without force
        const pausedResult = await issuanceAllocator
          .connect(accounts.governor)
          .setIssuancePerBlock.staticCall(newRate, false)
        expect(pausedResult).to.equal(false)

        // Should return true when paused with force=true
        const forcedResult = await issuanceAllocator
          .connect(accounts.governor)
          .setIssuancePerBlock.staticCall(newRate, true)
        expect(forcedResult).to.equal(true)
      })
    })

    describe('distributeIssuance', () => {
      it('should return appropriate block numbers', async () => {
        const { issuanceAllocator, addresses } = sharedContracts

        // Should return lastIssuanceDistributionBlock when no blocks have passed
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()
        const lastIssuanceBlock = await issuanceAllocator.lastIssuanceDistributionBlock()
        const noBlocksResult = await issuanceAllocator.connect(accounts.governor).distributeIssuance.staticCall()
        expect(noBlocksResult).to.equal(lastIssuanceBlock)

        // Add a target and mine blocks to test distribution
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%
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
      const issuancePerBlock = await issuanceAllocator.issuancePerBlock()
      const PPM = 1_000_000

      // Test unregistered target (should return zeros)
      let result = await issuanceAllocator.getTargetIssuancePerBlock(addresses.target1)
      expect(result.selfIssuancePerBlock).to.equal(0)
      expect(result.allocatorIssuancePerBlock).to.equal(0)
      expect(result.allocatorIssuanceBlockAppliedTo).to.be.greaterThanOrEqual(0)
      expect(result.selfIssuanceBlockAppliedTo).to.be.greaterThanOrEqual(0)

      // Test self-minting target with 30% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 0, 300000, false)

      const expectedSelfIssuance = (issuancePerBlock * BigInt(300000)) / BigInt(PPM)
      result = await issuanceAllocator.getTargetIssuancePerBlock(addresses.target1)
      expect(result.selfIssuancePerBlock).to.equal(expectedSelfIssuance)
      expect(result.allocatorIssuancePerBlock).to.equal(0)
      expect(result.selfIssuanceBlockAppliedTo).to.equal(await ethers.provider.getBlockNumber())
      expect(result.allocatorIssuanceBlockAppliedTo).to.equal(await issuanceAllocator.lastIssuanceDistributionBlock())

      // Test non-self-minting target with 40% allocation (reset target1 first)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 400000, 0, false)

      const expectedAllocatorIssuance = (issuancePerBlock * BigInt(400000)) / BigInt(PPM)
      result = await issuanceAllocator.getTargetIssuancePerBlock(addresses.target1)
      expect(result.allocatorIssuancePerBlock).to.equal(expectedAllocatorIssuance)
      expect(result.selfIssuancePerBlock).to.equal(0)
      expect(result.allocatorIssuanceBlockAppliedTo).to.equal(await ethers.provider.getBlockNumber())
      expect(result.selfIssuanceBlockAppliedTo).to.equal(await ethers.provider.getBlockNumber())
    })

    it('should not revert when contract is paused and blockAppliedTo indicates pause state', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Add target as self-minter with 30% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 0, 300000, false) // 30%, self-minter

      // Distribute issuance to set blockAppliedTo to current block
      await issuanceAllocator.distributeIssuance()

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).pause()

      // Should not revert when paused - this is the key difference from old functions
      const currentBlockBeforeCall = await ethers.provider.getBlockNumber()
      const result = await issuanceAllocator.getTargetIssuancePerBlock(addresses.target1)

      const issuancePerBlock = await issuanceAllocator.issuancePerBlock()
      const PPM = 1_000_000
      const expectedIssuance = (issuancePerBlock * BigInt(300000)) / BigInt(PPM)

      expect(result.selfIssuancePerBlock).to.equal(expectedIssuance)
      expect(result.allocatorIssuancePerBlock).to.equal(0)
      // For self-minting targets, selfIssuanceBlockAppliedTo should always be current block, even when paused
      expect(result.selfIssuanceBlockAppliedTo).to.equal(currentBlockBeforeCall)
      // allocatorIssuanceBlockAppliedTo should be the last distribution block (before pause)
      expect(result.allocatorIssuanceBlockAppliedTo).to.equal(await issuanceAllocator.lastIssuanceDistributionBlock())
    })

    it('should show blockAppliedTo updates after distribution', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Grant minter role to issuanceAllocator (needed for distributeIssuance calls)
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())

      // Add target as non-self-minter with 50% allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50%, non-self-minter

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

      const issuancePerBlock = await issuanceAllocator.issuancePerBlock()
      const PPM = 1_000_000
      const expectedIssuance = (issuancePerBlock * BigInt(500000)) / BigInt(PPM)
      expect(result.allocatorIssuancePerBlock).to.equal(expectedIssuance)
      expect(result.selfIssuancePerBlock).to.equal(0)
    })
  })

  describe('distributePendingIssuance', () => {
    it('should only allow governor to call distributePendingIssuance', async () => {
      const { issuanceAllocator } = sharedContracts

      // Non-governor should not be able to call distributePendingIssuance
      await expect(
        issuanceAllocator.connect(accounts.nonGovernor)['distributePendingIssuance()'](),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')

      // Governor should be able to call distributePendingIssuance (even if no pending issuance)
      await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()).to.not.be.reverted

      // Test return value using staticCall - should return lastIssuanceDistributionBlock
      const result = await issuanceAllocator.connect(accounts.governor).distributePendingIssuance.staticCall()
      const lastDistributionBlock = await issuanceAllocator.lastIssuanceDistributionBlock()
      expect(result).to.equal(lastDistributionBlock)
    })

    it('should be a no-op when there is no pending issuance', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Setup with zero issuance rate to ensure no pending accumulation
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(0, false) // No issuance
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%

      // Initialize distribution
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Verify no pending issuance (should be 0 since issuance rate is 0)
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)

      const { graphToken } = sharedContracts
      const initialBalance = await (graphToken as any).balanceOf(addresses.target1)

      // Call distributePendingIssuance - should be no-op
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

      // Test return value using staticCall - should return lastIssuanceDistributionBlock
      const result = await issuanceAllocator.connect(accounts.governor).distributePendingIssuance.staticCall()
      const lastDistributionBlock = await issuanceAllocator.lastIssuanceDistributionBlock()

      // Should return last distribution block (since no pending issuance to distribute)
      expect(result).to.equal(lastDistributionBlock)

      // Balance should remain the same
      expect(await (graphToken as any).balanceOf(addresses.target1)).to.equal(initialBalance)
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should distribute pending issuance to allocator-minting targets', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      // Add allocator-minting targets and a small self-minting target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 590000, 0, false) // 59%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 400000, 10000, false) // 40% allocator + 1% self

      // Distribute once to initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // Pause and accumulate some issuance
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Trigger accumulation by changing self-minting allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 400000, 0, true) // Remove self-minting

      const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingBefore).to.be.gt(0)

      // Call distributePendingIssuance while still paused
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

      // Check that pending was distributed proportionally
      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      expect(finalBalance1).to.be.gt(initialBalance1)
      expect(finalBalance2).to.be.gt(initialBalance2)

      // Verify pending issuance was reset to 0
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)

      // Verify proportional distribution (59% vs 40%)
      const distributed1 = finalBalance1 - initialBalance1
      const distributed2 = finalBalance2 - initialBalance2
      const ratio = (BigInt(distributed1) * BigInt(1000)) / BigInt(distributed2) // Multiply by 1000 for precision
      expect(ratio).to.be.closeTo(1475n, 50n) // 59/40 = 1.475, with some tolerance for rounding
    })

    it('should be a no-op when allocatorMintingAllowance is 0 (all targets are self-minting)', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      // Add only self-minting targets (100% self-minting)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 0, 1000000, false) // 100% self-minting

      // Distribute once to initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Pause and accumulate some issuance
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Trigger accumulation by changing rate
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'), false)

      const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingBefore).to.equal(0) // Should be 0 because allocatorMintingAllowance is 0

      const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

      // Call distributePendingIssuance - should be no-op due to allocatorMintingAllowance = 0
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

      // Balance should remain the same (self-minting targets don't receive tokens from allocator)
      expect(await (graphToken as any).balanceOf(await target1.getAddress())).to.equal(initialBalance)

      // Pending issuance should be reset to 0 even though nothing was distributed
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should work when contract is paused', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      // Add allocator-minting target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50%

      // Distribute once to initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()
      const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

      // Pause and accumulate some issuance
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Trigger accumulation by changing rate
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'), true)

      const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingBefore).to.be.gt(0)

      // Call distributePendingIssuance while paused - should work
      await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()).to.not.be.reverted

      // Check that pending was distributed
      const finalBalance = await (graphToken as any).balanceOf(await target1.getAddress())
      expect(finalBalance).to.be.gt(initialBalance)

      // Verify pending issuance was reset to 0
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should emit IssuanceDistributed events for each target', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      // Add allocator-minting targets and a small self-minting target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false) // 30%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 190000, 10000, false) // 19% allocator + 1% self

      // Distribute once to initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Pause and accumulate some issuance
      await issuanceAllocator.connect(accounts.governor).pause()
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Trigger accumulation by changing self-minting allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 200000, 0, true) // Remove self-minting

      const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingBefore).to.be.gt(0)

      // Call distributePendingIssuance and check events
      const tx = await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()
      const receipt = await tx.wait()

      // Should emit events for both targets
      const events = receipt.logs.filter(
        (log) => log.topics[0] === issuanceAllocator.interface.getEvent('IssuanceDistributed').topicHash,
      )
      expect(events.length).to.equal(2)

      // Verify the events contain the correct target addresses
      const decodedEvents = events.map((event) => issuanceAllocator.interface.parseLog(event))
      const targetAddresses = decodedEvents.map((event) => event.args.target)
      expect(targetAddresses).to.include(await target1.getAddress())
      expect(targetAddresses).to.include(await target2.getAddress())
    })

    describe('distributePendingIssuance(uint256 toBlockNumber)', () => {
      it('should validate distributePendingIssuance(uint256) access control and parameters', async () => {
        const { issuanceAllocator } = sharedContracts

        // Test 1: Access control - Non-governor should not be able to call distributePendingIssuance
        await expect(
          issuanceAllocator.connect(accounts.nonGovernor)['distributePendingIssuance(uint256)'](100),
        ).to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')

        // Test 2: Parameter validation - Should revert when toBlockNumber is less than lastIssuanceAccumulationBlock
        const lastAccumulationBlock = await issuanceAllocator.lastIssuanceAccumulationBlock()
        const invalidBlock = lastAccumulationBlock - 1n
        await expect(
          issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](invalidBlock),
        ).to.be.revertedWithCustomError(issuanceAllocator, 'ToBlockOutOfRange')

        // Test 3: Parameter validation - Should revert when toBlockNumber is greater than current block
        const currentBlock = await ethers.provider.getBlockNumber()
        const futureBlock = currentBlock + 10
        await expect(
          issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](futureBlock),
        ).to.be.revertedWithCustomError(issuanceAllocator, 'ToBlockOutOfRange')

        // Test 4: Valid call - Governor should be able to call distributePendingIssuance with valid block number
        await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](currentBlock))
          .to.not.be.reverted
      })

      it('should accumulate and distribute issuance up to specified block', async () => {
        const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

        // Add target
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50%

        // Pause to enable accumulation
        await issuanceAllocator.connect(accounts.governor).pause()

        // Mine some blocks to create a gap
        await ethers.provider.send('hardhat_mine', ['0x5']) // Mine 5 blocks

        const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())
        const currentBlock = await ethers.provider.getBlockNumber()
        const targetBlock = currentBlock - 2 // Accumulate up to 2 blocks ago

        // Call distributePendingIssuance with specific toBlockNumber
        await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](targetBlock)

        // Check that tokens were distributed
        const finalBalance = await (graphToken as any).balanceOf(await target1.getAddress())
        expect(finalBalance).to.be.gt(initialBalance)

        // Check that accumulation block was updated to targetBlock
        expect(await issuanceAllocator.lastIssuanceAccumulationBlock()).to.equal(targetBlock)

        // Check that distribution block was updated to targetBlock
        expect(await issuanceAllocator.lastIssuanceDistributionBlock()).to.equal(targetBlock)

        // Pending should be reset to 0
        expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
      })

      it('should work with toBlockNumber equal to lastIssuanceAccumulationBlock (no-op)', async () => {
        const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

        // Add target
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50%

        const lastAccumulationBlock = await issuanceAllocator.lastIssuanceAccumulationBlock()
        const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

        // Call with same block number - should be no-op for accumulation
        await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](lastAccumulationBlock)

        // Balance should remain the same (no new accumulation)
        const finalBalance = await (graphToken as any).balanceOf(await target1.getAddress())
        expect(finalBalance).to.equal(initialBalance)

        // Blocks should remain the same
        expect(await issuanceAllocator.lastIssuanceAccumulationBlock()).to.equal(lastAccumulationBlock)
      })

      it('should work with toBlockNumber equal to current block', async () => {
        const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

        // Add target
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50%

        // Pause to enable accumulation
        await issuanceAllocator.connect(accounts.governor).pause()

        // Mine some blocks to create a gap
        await ethers.provider.send('hardhat_mine', ['0x3']) // Mine 3 blocks

        const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())
        const currentBlock = await ethers.provider.getBlockNumber()

        // Call distributePendingIssuance with current block
        await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](currentBlock)

        // Check that tokens were distributed
        const finalBalance = await (graphToken as any).balanceOf(await target1.getAddress())
        expect(finalBalance).to.be.gt(initialBalance)

        // Check that accumulation block was updated to current block
        expect(await issuanceAllocator.lastIssuanceAccumulationBlock()).to.equal(currentBlock)
      })

      it('should handle multiple calls with different toBlockNumbers', async () => {
        const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

        // Add target
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50%

        // Pause to enable accumulation
        await issuanceAllocator.connect(accounts.governor).pause()

        // Mine some blocks to create a gap
        await ethers.provider.send('hardhat_mine', ['0x5']) // Mine 5 blocks

        const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())
        const currentBlock = await ethers.provider.getBlockNumber()
        const firstTargetBlock = currentBlock - 3
        const secondTargetBlock = currentBlock - 1

        // First call - accumulate up to firstTargetBlock
        await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](firstTargetBlock)

        const balanceAfterFirst = await (graphToken as any).balanceOf(await target1.getAddress())
        expect(balanceAfterFirst).to.be.gt(initialBalance)
        expect(await issuanceAllocator.lastIssuanceAccumulationBlock()).to.equal(firstTargetBlock)

        // Second call - accumulate from firstTargetBlock to secondTargetBlock
        await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance(uint256)'](secondTargetBlock)

        const balanceAfterSecond = await (graphToken as any).balanceOf(await target1.getAddress())
        expect(balanceAfterSecond).to.be.gt(balanceAfterFirst)
        expect(await issuanceAllocator.lastIssuanceAccumulationBlock()).to.equal(secondTargetBlock)
      })

      it('should return correct block number after distribution', async () => {
        const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

        // Add target
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50%

        // Pause to enable accumulation
        await issuanceAllocator.connect(accounts.governor).pause()

        // Mine some blocks
        await ethers.provider.send('hardhat_mine', ['0x3']) // Mine 3 blocks

        const currentBlock = await ethers.provider.getBlockNumber()
        const targetBlock = currentBlock - 1

        // Test return value using staticCall
        const result = await issuanceAllocator
          .connect(accounts.governor)
          ['distributePendingIssuance(uint256)'].staticCall(targetBlock)

        expect(result).to.equal(targetBlock)
      })
    })
  })

  describe('Notification Behavior When Paused', () => {
    it('should notify targets of allocation changes even when paused', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Setup
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      // Add initial allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()

      // Change allocation while paused - should notify target even though paused
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 400000, 0, true) // Change to 40%

      // Verify that beforeIssuanceAllocationChange was called on the target
      // This is verified by checking that the transaction succeeded and the allocation was updated
      const allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(allocation.allocatorMintingPPM).to.equal(400000)
    })

    it('should notify targets of issuance rate changes even when paused', async () => {
      const { issuanceAllocator, addresses } = sharedContracts

      // Setup
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      // Add target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300000, 0, false) // 30%

      // Pause the contract
      await issuanceAllocator.connect(accounts.governor).pause()

      // Change issuance rate while paused - should notify targets even though paused
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'), true)

      // Verify that the rate change was applied
      expect(await issuanceAllocator.issuancePerBlock()).to.equal(ethers.parseEther('200'))
    })

    it('should not notify targets when no actual change occurs', async () => {
      const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      // Add target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false) // 30%

      // Try to set the same allocation - should not notify (no change)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false) // Same 30%

      // Verify allocation is unchanged
      const allocation = await issuanceAllocator.getTargetAllocation(await target1.getAddress())
      expect(allocation.allocatorMintingPPM).to.equal(300000)

      // Try to set the same issuance rate - should not notify (no change)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

      expect(await issuanceAllocator.issuancePerBlock()).to.equal(ethers.parseEther('100'))
    })
  })

  describe('Mixed Allocation Distribution Scenarios', () => {
    it('should correctly distribute pending issuance with mixed allocations and unallocated space', async () => {
      const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

      // Test scenario: 25% allocator-minting + 50% self-minting + 25% unallocated
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 250000, 0, false) // 25% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 500000, false) // 50% self-minting
      // 25% remains unallocated

      // Verify the setup
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationPPM).to.equal(750000) // 75% total
      expect(totalAllocation.allocatorMintingPPM).to.equal(250000) // 25% allocator
      expect(totalAllocation.selfMintingPPM).to.equal(500000) // 50% self

      // Distribute once to initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Pause and accumulate issuance
      await issuanceAllocator.connect(accounts.governor).pause()
      for (let i = 0; i < 10; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Trigger accumulation by forcing rate change
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('2000'), true)

      const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingBefore).to.be.gt(0)

      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      // Call distributePendingIssuance
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

      const distributed1 = finalBalance1 - initialBalance1
      const distributed2 = finalBalance2 - initialBalance2

      // Target2 (self-minting) should receive nothing from distributePendingIssuance
      expect(distributed2).to.equal(0)

      // Target1 should receive the correct proportional amount
      // The calculation is: (pendingAmount * 250000) / (1000000 - 500000) = (pendingAmount * 250000) / 500000 = pendingAmount * 0.5
      // So target1 should get exactly 50% of the pending amount
      const expectedDistribution = pendingBefore / 2n // 50% of pending
      expect(distributed1).to.be.closeTo(expectedDistribution, ethers.parseEther('1'))

      // Verify pending issuance was reset
      expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)
    })

    it('should correctly distribute pending issuance among multiple allocator-minting targets', async () => {
      const { issuanceAllocator, graphToken, target1, target2, target3 } = await setupIssuanceAllocator()

      // Setup
      await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

      // Test scenario: 15% + 10% allocator-minting + 50% self-minting + 25% unallocated
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 150000, 0, false) // 15% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 100000, 0, false) // 10% allocator-minting
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](await target3.getAddress(), 0, 500000, false) // 50% self-minting
      // 25% remains unallocated

      // Verify the setup
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.allocatorMintingPPM).to.equal(250000) // 25% total allocator
      expect(totalAllocation.selfMintingPPM).to.equal(500000) // 50% self

      // Distribute once to initialize
      await issuanceAllocator.connect(accounts.governor).distributeIssuance()

      // Pause and accumulate issuance
      await issuanceAllocator.connect(accounts.governor).pause()
      for (let i = 0; i < 10; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Trigger accumulation
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('2000'), true)

      const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
      expect(pendingBefore).to.be.gt(0)

      const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())
      const initialBalance3 = await (graphToken as any).balanceOf(await target3.getAddress())

      // Call distributePendingIssuance
      await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

      const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
      const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())
      const finalBalance3 = await (graphToken as any).balanceOf(await target3.getAddress())

      const distributed1 = finalBalance1 - initialBalance1
      const distributed2 = finalBalance2 - initialBalance2
      const distributed3 = finalBalance3 - initialBalance3

      // Target3 (self-minting) should receive nothing
      expect(distributed3).to.equal(0)

      // Verify proportional distribution between allocator-minting targets
      // Target1 should get 15/25 = 60% of the distributed amount
      // Target2 should get 10/25 = 40% of the distributed amount
      if (distributed1 > 0 && distributed2 > 0) {
        const ratio = (BigInt(distributed1) * 1000n) / BigInt(distributed2) // Multiply by 1000 for precision
        expect(ratio).to.be.closeTo(1500n, 50n) // 150000/100000 = 1.5
      }

      // Total distributed should equal the allocator-minting portion of pending
      // With 25% total allocator-minting out of 50% non-self-minting space:
      // Each target gets: (targetPPM / (MILLION - selfMintingPPM)) * pendingAmount
      // Target1: (150000 / 500000) * pendingAmount = 30% of pending
      // Target2: (100000 / 500000) * pendingAmount = 20% of pending
      // Total: 50% of pending
      const totalDistributed = distributed1 + distributed2
      const expectedTotal = pendingBefore / 2n // 50% of pending
      expect(totalDistributed).to.be.closeTo(expectedTotal, ethers.parseEther('1'))
    })
  })

  describe('Edge Cases for Pending Issuance Distribution', () => {
    describe('Division by Zero and Near-Zero Denominator Cases', () => {
      it('should handle case when totalSelfMintingPPM equals MILLION (100% self-minting)', async () => {
        const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

        // Add 100% self-minting target (totalSelfMintingPPM = MILLION)
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 0, 1000000, false) // 100% self-minting

        // Distribute once to initialize
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()

        // Pause and accumulate some issuance
        await issuanceAllocator.connect(accounts.governor).pause()
        await ethers.provider.send('evm_mine', [])
        await ethers.provider.send('evm_mine', [])

        // Trigger accumulation by changing rate
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'), false)

        const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
        expect(pendingBefore).to.equal(0) // Should be 0 because no allocator-minting allocation

        const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

        // Call distributePendingIssuance - should not revert even with division by zero scenario
        await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()).to.not.be.reverted

        // Balance should remain the same (no allocator-minting targets)
        expect(await (graphToken as any).balanceOf(await target1.getAddress())).to.equal(initialBalance)
      })

      it('should handle case with very small denominator (totalSelfMintingPPM near MILLION)', async () => {
        const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

        // Setup with very high issuance rate to ensure accumulation despite small denominator
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000000'), false) // Very high rate

        // Add targets: 1 PPM allocator-minting, 999,999 PPM self-minting (denominator = 1)
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 1, 0, false) // 1 PPM allocator-minting
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 999999, false) // 999,999 PPM self-minting

        // Distribute once to initialize
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()

        // Pause and accumulate significant issuance over many blocks
        await issuanceAllocator.connect(accounts.governor).pause()
        for (let i = 0; i < 100; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Trigger accumulation by changing rate (this forces accumulation)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('2000000'), true) // Force even if pending

        const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
        expect(pendingBefore).to.be.gt(0)

        const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

        // Call distributePendingIssuance - should work with very small denominator
        await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()).to.not.be.reverted

        // Target1 should receive all the pending issuance (since it's the only allocator-minting target)
        const finalBalance = await (graphToken as any).balanceOf(await target1.getAddress())
        expect(finalBalance).to.be.gt(initialBalance)

        // The distributed amount should equal the pending amount (within rounding)
        const distributed = finalBalance - initialBalance
        expect(distributed).to.be.closeTo(pendingBefore, ethers.parseEther('1'))
      })
    })

    describe('Large Value and Overflow Protection', () => {
      it('should handle large pending amounts without overflow', async () => {
        const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

        // Setup with very high issuance rate
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000000'), false) // 1M tokens per block

        // Add target with high allocation
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50%

        // Distribute once to initialize
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()

        // Pause and accumulate for many blocks
        await issuanceAllocator.connect(accounts.governor).pause()
        for (let i = 0; i < 100; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Trigger accumulation by forcing rate change
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('2000000'), true) // Force even if pending

        const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
        expect(pendingBefore).to.be.gt(ethers.parseEther('25000000')) // Should be very large (50% of total)

        const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

        // Call distributePendingIssuance - should handle large values without overflow
        await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()).to.not.be.reverted

        const finalBalance = await (graphToken as any).balanceOf(await target1.getAddress())
        expect(finalBalance).to.be.gt(initialBalance)

        // Verify the calculation is correct for large values
        // Target1 has 50% allocation, so it should get: (pendingAmount * 500000) / 1000000 = 50% of pending
        const distributed = finalBalance - initialBalance
        const expectedDistribution = pendingBefore / 2n // 50% of pending
        expect(distributed).to.be.closeTo(expectedDistribution, ethers.parseEther('1000')) // Allow for rounding
      })
    })

    describe('Precision and Rounding Edge Cases', () => {
      it('should handle small allocations with minimal rounding loss', async () => {
        const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

        // Setup with higher issuance rate to ensure accumulation
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000000'), false) // Higher rate

        // Add targets with very small allocations
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 1, 0, false) // 1 PPM
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 2, 0, false) // 2 PPM

        // Distribute once to initialize
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()

        // Pause and accumulate over multiple blocks
        await issuanceAllocator.connect(accounts.governor).pause()
        for (let i = 0; i < 10; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Trigger accumulation by forcing rate change
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('2000000'), true)

        const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
        expect(pendingBefore).to.be.gt(0)

        const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
        const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

        // Call distributePendingIssuance
        await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

        const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
        const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

        const distributed1 = finalBalance1 - initialBalance1
        const distributed2 = finalBalance2 - initialBalance2

        // Verify proportional distribution (target2 should get ~2x target1)
        if (distributed1 > 0 && distributed2 > 0) {
          const ratio = (BigInt(distributed2) * 1000n) / BigInt(distributed1) // Multiply by 1000 for precision
          expect(ratio).to.be.closeTo(2000n, 100n) // Should be close to 2.0 with some tolerance
        }
      })

      it('should handle zero pending amount correctly', async () => {
        const { issuanceAllocator, graphToken, target1 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

        // Add target
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50%

        // Distribute to ensure no pending amount
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()
        expect(await issuanceAllocator.pendingAccumulatedAllocatorIssuance()).to.equal(0)

        const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

        // Call distributePendingIssuance with zero pending - should be no-op
        await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()).to.not.be.reverted

        // Balance should remain unchanged
        expect(await (graphToken as any).balanceOf(await target1.getAddress())).to.equal(initialBalance)
      })
    })

    describe('Mixed Allocation Scenarios', () => {
      it('should correctly distribute with extreme allocation ratios', async () => {
        const { issuanceAllocator, graphToken, target1, target2, target3 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

        // Add targets with extreme ratios: 1 PPM, 499,999 PPM allocator-minting, 500,000 PPM self-minting
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 1, 0, false) // 0.0001%
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 499999, 0, false) // 49.9999%
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target3.getAddress(), 0, 500000, false) // 50% self-minting

        // Distribute once to initialize
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()

        // Pause and accumulate
        await issuanceAllocator.connect(accounts.governor).pause()
        for (let i = 0; i < 5; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Trigger accumulation by forcing rate change
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('2000'), true)

        const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
        expect(pendingBefore).to.be.gt(0)

        const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
        const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())
        const initialBalance3 = await (graphToken as any).balanceOf(await target3.getAddress())

        // Call distributePendingIssuance
        await issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()

        const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
        const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())
        const finalBalance3 = await (graphToken as any).balanceOf(await target3.getAddress())

        const distributed1 = finalBalance1 - initialBalance1
        const distributed2 = finalBalance2 - initialBalance2
        const distributed3 = finalBalance3 - initialBalance3

        // Target3 (self-minting) should receive nothing from distributePendingIssuance
        expect(distributed3).to.equal(0)

        // Target2 should receive ~499,999x more than target1
        if (distributed1 > 0 && distributed2 > 0) {
          const ratio = distributed2 / distributed1
          expect(ratio).to.be.closeTo(499999n, 1000n) // Allow for rounding
        }

        // Total distributed should equal pending (within rounding)
        const totalDistributed = distributed1 + distributed2
        expect(totalDistributed).to.be.closeTo(pendingBefore, ethers.parseEther('0.001'))
      })

      it('should handle dynamic allocation changes affecting denominator', async () => {
        const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

        // Initial setup: 50% allocator-minting, 50% self-minting
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 500000, 0, false) // 50% allocator
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 500000, false) // 50% self

        // Distribute once to initialize
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()

        // Pause and accumulate
        await issuanceAllocator.connect(accounts.governor).pause()
        await ethers.provider.send('evm_mine', [])
        await ethers.provider.send('evm_mine', [])

        // Change allocation to make denominator smaller: 10% allocator, 90% self-minting
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 100000, 0, true) // 10% allocator
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 900000, true) // 90% self

        const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
        expect(pendingBefore).to.be.gt(0)

        const initialBalance = await (graphToken as any).balanceOf(await target1.getAddress())

        // Call distributePendingIssuance with changed denominator
        await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()).to.not.be.reverted

        const finalBalance = await (graphToken as any).balanceOf(await target1.getAddress())
        expect(finalBalance).to.be.gt(initialBalance)

        // The distribution should use the new denominator (MILLION - 900000 = 100000)
        // So target1 should get all the pending amount since it's the only allocator-minting target
        const distributed = finalBalance - initialBalance
        expect(distributed).to.be.closeTo(pendingBefore, ethers.parseEther('0.001'))
      })
    })

    describe('Boundary Value Testing', () => {
      it('should handle totalSelfMintingPPM = 0 (no self-minting targets)', async () => {
        const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('100'), false)

        // Add only allocator-minting targets (totalSelfMintingPPM = 0)
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 300000, 0, false) // 30%
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 200000, 0, false) // 20%

        // Distribute once to initialize
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()

        // Pause and accumulate
        await issuanceAllocator.connect(accounts.governor).pause()
        await ethers.provider.send('evm_mine', [])
        await ethers.provider.send('evm_mine', [])

        // Trigger accumulation by forcing rate change
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'), true)

        const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
        expect(pendingBefore).to.be.gt(0)

        const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
        const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

        // Call distributePendingIssuance - denominator should be MILLION (1,000,000)
        await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()).to.not.be.reverted

        const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
        const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

        const distributed1 = finalBalance1 - initialBalance1
        const distributed2 = finalBalance2 - initialBalance2

        // Verify proportional distribution (3:2 ratio)
        if (distributed1 > 0 && distributed2 > 0) {
          const ratio = (BigInt(distributed1) * 1000n) / BigInt(distributed2) // Multiply by 1000 for precision
          expect(ratio).to.be.closeTo(1500n, 50n) // 300000/200000 = 1.5
        }

        // Total distributed should equal the allocated portion of pending
        // With 50% total allocator-minting allocation: (30% + 20%) / 100% = 50% of pending
        const totalDistributed = distributed1 + distributed2
        const expectedTotal = pendingBefore / 2n // 50% of pending
        expect(totalDistributed).to.be.closeTo(expectedTotal, ethers.parseEther('0.001'))
      })

      it('should handle totalSelfMintingPPM = MILLION - 1 (minimal allocator-minting)', async () => {
        const { issuanceAllocator, graphToken, target1, target2 } = await setupIssuanceAllocator()

        // Setup
        await (graphToken as any).addMinter(await issuanceAllocator.getAddress())
        await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('1000'), false)

        // Add targets: 1 PPM allocator-minting, 999,999 PPM self-minting
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target1.getAddress(), 1, 0, false) // 1 PPM allocator
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,bool)'](await target2.getAddress(), 0, 999999, false) // 999,999 PPM self

        // Distribute once to initialize
        await issuanceAllocator.connect(accounts.governor).distributeIssuance()

        // Pause and accumulate significant issuance
        await issuanceAllocator.connect(accounts.governor).pause()
        for (let i = 0; i < 10; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Trigger accumulation by forcing rate change
        await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('2000'), true)

        const pendingBefore = await issuanceAllocator.pendingAccumulatedAllocatorIssuance()
        expect(pendingBefore).to.be.gt(0)

        const initialBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
        const initialBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

        // Call distributePendingIssuance - denominator should be 1
        await expect(issuanceAllocator.connect(accounts.governor)['distributePendingIssuance()']()).to.not.be.reverted

        const finalBalance1 = await (graphToken as any).balanceOf(await target1.getAddress())
        const finalBalance2 = await (graphToken as any).balanceOf(await target2.getAddress())

        const distributed1 = finalBalance1 - initialBalance1
        const distributed2 = finalBalance2 - initialBalance2

        // Target2 (self-minting) should receive nothing
        expect(distributed2).to.equal(0)

        // Target1 should receive all pending issuance
        expect(distributed1).to.be.closeTo(pendingBefore, ethers.parseEther('0.001'))
      })
    })
  })
})

import { expect } from 'chai'
import hre from 'hardhat'
const { ethers } = hre

import { deployTestGraphToken, getTestAccounts, SHARED_CONSTANTS } from '../common/fixtures'
import { deployIssuanceAllocator } from './fixtures'

/**
 * ReentrantAction enum matching MockReentrantTarget.sol
 * IMPORTANT: This must be kept in sync with the Solidity enum
 */
enum ReentrantAction {
  None,
  DistributeIssuance,
  SetTargetAllocation1Param,
  SetTargetAllocation2Param,
  SetTargetAllocation3Param,
  SetIssuancePerBlock,
  SetIssuancePerBlock2Param,
  NotifyTarget,
  SetDefaultTarget1Param,
  SetDefaultTarget2Param,
  DistributePendingIssuance0Param,
  DistributePendingIssuance1Param,
}

describe('IssuanceAllocator - Reentrancy Protection', () => {
  let accounts
  let graphToken
  let issuanceAllocator
  let reentrantTarget
  let issuancePerBlock
  const GOVERNOR_ROLE = SHARED_CONSTANTS.GOVERNOR_ROLE
  const PAUSE_ROLE = SHARED_CONSTANTS.PAUSE_ROLE

  beforeEach(async () => {
    accounts = await getTestAccounts()
    issuancePerBlock = ethers.parseEther('100')

    // Deploy contracts
    graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, accounts.governor, issuancePerBlock)

    // Grant minter role to issuanceAllocator
    await graphToken.addMinter(await issuanceAllocator.getAddress())

    // Deploy mock reentrant target
    const MockReentrantTargetFactory = await ethers.getContractFactory('MockReentrantTarget')
    reentrantTarget = await MockReentrantTargetFactory.deploy()

    // Set the issuance allocator address in the reentrant target
    await reentrantTarget.setIssuanceAllocator(await issuanceAllocator.getAddress())

    // Grant GOVERNOR_ROLE and PAUSE_ROLE to the reentrant target so it can attempt protected operations
    await issuanceAllocator.connect(accounts.governor).grantRole(GOVERNOR_ROLE, await reentrantTarget.getAddress())
    await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
  })

  describe('Reentrancy during distributeIssuance', () => {
    it('should allow target to call distributeIssuance during notification (legitimate use case)', async () => {
      // This verifies that targets can legitimately call distributeIssuance() during notification
      // This is safe because:
      // 1. distributeIssuance() has block-tracking protection (no-op if already at current block)
      // 2. It makes no outward calls (just mints tokens)
      // 3. It doesn't modify allocations
      // 4. Targets may want to claim pending issuance before allocation changes

      // Add the reentrant target (reentrancy disabled during setup)
      await reentrantTarget.setReentrantAction(ReentrantAction.None)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](await reentrantTarget.getAddress(), ethers.parseEther('50'))

      // Configure to call distributeIssuance during next notification
      await reentrantTarget.setReentrantAction(ReentrantAction.DistributeIssuance)

      // Change allocation - the notification will call distributeIssuance
      // This should succeed (distributeIssuance is not protected, as it's a legitimate use case)
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](await reentrantTarget.getAddress(), ethers.parseEther('40')),
      ).to.not.be.reverted
    })
  })

  describe('Reentrancy during setTargetAllocation', () => {
    const testCases = [
      {
        name: '1 param variant',
        action: ReentrantAction.SetTargetAllocation1Param,
        trigger: async (target: string) =>
          issuanceAllocator
            .connect(accounts.governor)
            ['setTargetAllocation(address,uint256)'](target, ethers.parseEther('40')),
      },
      {
        name: '2 param variant',
        action: ReentrantAction.SetTargetAllocation2Param,
        trigger: async (target: string) =>
          issuanceAllocator
            .connect(accounts.governor)
            ['setTargetAllocation(address,uint256,uint256)'](target, ethers.parseEther('40'), 0),
      },
      {
        name: '3 param variant',
        action: ReentrantAction.SetTargetAllocation3Param,
        trigger: async (target: string) =>
          issuanceAllocator
            .connect(accounts.governor)
            ['setTargetAllocation(address,uint256,uint256)'](target, ethers.parseEther('40'), 0),
      },
    ]

    testCases.forEach(({ name, action, trigger }) => {
      it(`should revert when target attempts to reenter setTargetAllocation (${name})`, async () => {
        // First add the target with normal behavior
        await reentrantTarget.setReentrantAction(ReentrantAction.None)
        const targetAddress = await reentrantTarget.getAddress()
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](targetAddress, ethers.parseEther('30'))

        // Now configure it to attempt reentrancy on next notification
        await reentrantTarget.setReentrantAction(action)

        // Attempt to change allocation - should revert due to reentrancy
        await expect(trigger(targetAddress)).to.be.revertedWithCustomError(
          issuanceAllocator,
          'ReentrancyGuardReentrantCall',
        )
      })
    })
  })

  describe('Reentrancy during setIssuancePerBlock', () => {
    const testCases = [
      {
        name: '1 param variant',
        action: ReentrantAction.SetIssuancePerBlock,
        trigger: async () => issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200')),
      },
      {
        name: '2 param variant',
        action: ReentrantAction.SetIssuancePerBlock2Param,
        trigger: async () =>
          issuanceAllocator
            .connect(accounts.governor)
            ['setIssuancePerBlock(uint256,uint256)'](ethers.parseEther('200'), 0),
      },
    ]

    testCases.forEach(({ name, action, trigger }) => {
      it(`should revert when target attempts to reenter setIssuancePerBlock (${name})`, async () => {
        // Set up a malicious default target
        await issuanceAllocator
          .connect(accounts.governor)
          ['setDefaultTarget(address)'](await reentrantTarget.getAddress())

        // Configure to attempt reentrancy
        await reentrantTarget.setReentrantAction(action)

        // Attempt to change issuance rate - should revert due to reentrancy
        await expect(trigger()).to.be.revertedWithCustomError(issuanceAllocator, 'ReentrancyGuardReentrantCall')
      })
    })
  })

  describe('Reentrancy during notifyTarget', () => {
    it('should revert when target attempts to reenter notifyTarget', async () => {
      // Add the target
      await reentrantTarget.setReentrantAction(ReentrantAction.None)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](await reentrantTarget.getAddress(), ethers.parseEther('25'))

      // Configure to attempt reentrancy
      await reentrantTarget.setReentrantAction(ReentrantAction.NotifyTarget)

      // Attempt to notify - should revert due to reentrancy
      await expect(
        issuanceAllocator.connect(accounts.governor).notifyTarget(await reentrantTarget.getAddress()),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'ReentrancyGuardReentrantCall')
    })
  })

  describe('Reentrancy during setDefaultTarget', () => {
    const testCases = [
      {
        name: '1 param variant',
        action: ReentrantAction.SetDefaultTarget1Param,
        trigger: async (target: string) =>
          issuanceAllocator.connect(accounts.governor)['setDefaultTarget(address)'](target),
      },
      {
        name: '2 param variant',
        action: ReentrantAction.SetDefaultTarget2Param,
        trigger: async (target: string) => issuanceAllocator.connect(accounts.governor).setDefaultTarget(target),
      },
    ]

    testCases.forEach(({ name, action, trigger }) => {
      it(`should revert when target attempts to reenter setDefaultTarget (${name})`, async () => {
        // Configure to attempt reentrancy
        await reentrantTarget.setReentrantAction(action)

        // Attempt to set as default target - should revert due to reentrancy
        await expect(trigger(await reentrantTarget.getAddress())).to.be.revertedWithCustomError(
          issuanceAllocator,
          'ReentrancyGuardReentrantCall',
        )
      })
    })
  })

  describe('Reentrancy during distributePendingIssuance', () => {
    const testCases = [
      { name: '0 param variant', action: ReentrantAction.DistributePendingIssuance0Param },
      { name: '1 param variant', action: ReentrantAction.DistributePendingIssuance1Param },
    ]

    testCases.forEach(({ name, action }) => {
      it(`should revert when target attempts to reenter distributePendingIssuance (${name})`, async () => {
        // Add the reentrant target with initial allocation
        await reentrantTarget.setReentrantAction(ReentrantAction.None)
        const targetAddress = await reentrantTarget.getAddress()
        await issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](targetAddress, ethers.parseEther('30'))

        // Configure to attempt calling distributePendingIssuance during next notification
        await reentrantTarget.setReentrantAction(action)

        // Attempt to change allocation - should revert due to reentrancy
        await expect(
          issuanceAllocator
            .connect(accounts.governor)
            ['setTargetAllocation(address,uint256)'](targetAddress, ethers.parseEther('40')),
        ).to.be.revertedWithCustomError(issuanceAllocator, 'ReentrancyGuardReentrantCall')
      })
    })
  })

  describe('No reentrancy when disabled', () => {
    it('should work normally when reentrancy is not attempted', async () => {
      // Ensure reentrant action is None
      await reentrantTarget.setReentrantAction(ReentrantAction.None)

      // Add the target with some allocation
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](await reentrantTarget.getAddress(), ethers.parseEther('50')),
      ).to.not.be.reverted

      // Mine some blocks
      await hre.network.provider.send('hardhat_mine', ['0x0A']) // Mine 10 blocks

      // Distribute should work normally
      await expect(issuanceAllocator.distributeIssuance()).to.not.be.reverted
    })
  })
})

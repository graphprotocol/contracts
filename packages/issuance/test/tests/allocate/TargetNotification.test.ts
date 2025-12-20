import { expect } from 'chai'
import hre from 'hardhat'

const { ethers } = hre

import { getTestAccounts } from '../common/fixtures'
import { deployTestGraphToken } from '../common/fixtures'
import { deployIssuanceAllocator } from './fixtures'

describe('IssuanceAllocator - Target Notification', () => {
  let accounts
  let addresses: {
    target1: string
    target2: string
    defaultTarget: string
  }

  let issuanceAllocator
  let graphToken
  let target1
  let target2
  let defaultTarget

  const issuancePerBlock = ethers.parseEther('100')

  beforeEach(async () => {
    // Get test accounts
    accounts = await getTestAccounts()

    // Deploy GraphToken
    graphToken = await deployTestGraphToken()

    // Deploy IssuanceAllocator
    issuanceAllocator = await deployIssuanceAllocator(
      await graphToken.getAddress(),
      accounts.governor,
      issuancePerBlock,
    )

    // Grant minter role to IssuanceAllocator
    await graphToken.addMinter(await issuanceAllocator.getAddress())

    // Deploy mock notification trackers
    const MockNotificationTracker = await ethers.getContractFactory('MockNotificationTracker')
    target1 = await MockNotificationTracker.deploy()
    target2 = await MockNotificationTracker.deploy()
    defaultTarget = await MockNotificationTracker.deploy()

    addresses = {
      target1: await target1.getAddress(),
      target2: await target2.getAddress(),
      defaultTarget: await defaultTarget.getAddress(),
    }
  })

  describe('setTargetAllocation notifications', () => {
    it('should notify both target and default target when setting allocation', async () => {
      // Set a non-zero default target first
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.defaultTarget)

      // Verify initial state
      expect(await target1.notificationCount()).to.equal(0)
      expect(await defaultTarget.notificationCount()).to.equal(1) // Notified during setDefaultTarget

      // Reset notification count for clean test
      await defaultTarget.resetNotificationCount()

      // Set allocation for target1 - should notify BOTH target1 and defaultTarget
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('30'))

      // Verify both targets were notified
      expect(await target1.notificationCount()).to.equal(1)
      expect(await defaultTarget.notificationCount()).to.equal(1)
    })

    it('should notify both targets when changing existing allocation', async () => {
      // Set a non-zero default target
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.defaultTarget)

      // Set initial allocation for target1
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('30'))

      // Reset counters
      await target1.resetNotificationCount()
      await defaultTarget.resetNotificationCount()

      // Change allocation for target1
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('50'))

      // Both should be notified again
      expect(await target1.notificationCount()).to.equal(1)
      expect(await defaultTarget.notificationCount()).to.equal(1)
    })

    it('should notify both targets when removing allocation', async () => {
      // Set a non-zero default target
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.defaultTarget)

      // Set initial allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('30'))

      // Reset counters
      await target1.resetNotificationCount()
      await defaultTarget.resetNotificationCount()

      // Remove allocation (set to 0)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 0, 0)

      // Both should be notified
      expect(await target1.notificationCount()).to.equal(1)
      expect(await defaultTarget.notificationCount()).to.equal(1)
    })

    it('should notify default target even when it is address(0)', async () => {
      // Default is address(0) by default, which should handle notification gracefully
      expect(await issuanceAllocator.getTargetAt(0)).to.equal(ethers.ZeroAddress)

      // Set allocation for target1 - should not revert even though default is address(0)
      await expect(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('30')),
      ).to.not.be.reverted

      // Target1 should be notified
      expect(await target1.notificationCount()).to.equal(1)
    })

    it('should notify correct targets when setting multiple allocations', async () => {
      // Set a non-zero default target
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.defaultTarget)
      await defaultTarget.resetNotificationCount()

      // Set allocation for target1
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('30'))

      expect(await target1.notificationCount()).to.equal(1)
      expect(await target2.notificationCount()).to.equal(0)
      expect(await defaultTarget.notificationCount()).to.equal(1)

      // Reset counters
      await target1.resetNotificationCount()
      await defaultTarget.resetNotificationCount()

      // Set allocation for target2
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, ethers.parseEther('20'))

      // Only target2 and default should be notified (not target1)
      expect(await target1.notificationCount()).to.equal(0)
      expect(await target2.notificationCount()).to.equal(1)
      expect(await defaultTarget.notificationCount()).to.equal(1)
    })

    it('should emit NotificationReceived events for both targets', async () => {
      // Set a non-zero default target
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.defaultTarget)
      await defaultTarget.resetNotificationCount()

      // Set allocation and check for events from both mock targets
      const tx = await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('30'))

      // Both targets should emit their NotificationReceived events
      await expect(tx).to.emit(target1, 'NotificationReceived')
      await expect(tx).to.emit(defaultTarget, 'NotificationReceived')
    })
  })

  describe('setIssuancePerBlock notifications', () => {
    it('should notify only default target when changing issuance rate', async () => {
      // Set a non-zero default target
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.defaultTarget)

      // Add a regular target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('30'))

      // Reset counters
      await target1.resetNotificationCount()
      await defaultTarget.resetNotificationCount()

      // Change issuance rate
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'))

      // Only default should be notified (regular targets keep same absolute rates)
      expect(await target1.notificationCount()).to.equal(0)
      expect(await defaultTarget.notificationCount()).to.equal(1)
    })
  })

  describe('setDefaultTarget notifications', () => {
    it('should notify both old and new default targets', async () => {
      // Set first default target
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target1)

      // Reset counter
      await target1.resetNotificationCount()

      // Change to new default target - should notify both
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target2)

      // Both old and new default should be notified
      expect(await target1.notificationCount()).to.equal(1)
      expect(await target2.notificationCount()).to.equal(1)
    })
  })

  describe('notification deduplication', () => {
    it('should not notify target twice in the same block', async () => {
      // Set a non-zero default target
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.defaultTarget)
      await defaultTarget.resetNotificationCount()

      // Try to set the same allocation twice in same block (second should be no-op)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('30'))

      // Should only be notified once
      expect(await target1.notificationCount()).to.equal(1)
      expect(await defaultTarget.notificationCount()).to.equal(1)

      // Second call with same values should not notify again (no change)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethers.parseEther('30'))

      // Counts should remain the same (no new notifications)
      expect(await target1.notificationCount()).to.equal(1)
      expect(await defaultTarget.notificationCount()).to.equal(1)
    })
  })
})

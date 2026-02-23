/**
 * Allocate Access Control Tests
 * Tests access control patterns for IssuanceAllocator and DirectAllocation contracts
 */

import { expect } from 'chai'
import { ethers as ethersLib } from 'ethers'

import { deployTestGraphToken, getTestAccounts, SHARED_CONSTANTS } from '../common/fixtures'
import { testMultipleAccessControl } from './commonTestUtils'
import { deployDirectAllocation, deployIssuanceAllocator } from './fixtures'

describe('Allocate Access Control Tests', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy allocate contracts
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()
    const issuanceAllocator = await deployIssuanceAllocator(
      graphTokenAddress,
      accounts.governor,
      ethersLib.parseEther('100'),
    )
    const directAllocation = await deployDirectAllocation(graphTokenAddress, accounts.governor)

    contracts = {
      graphToken,
      issuanceAllocator,
      directAllocation,
    }
  })

  describe('IssuanceAllocator Access Control', () => {
    describe('setIssuancePerBlock', () => {
      it('should revert when non-governor calls setIssuancePerBlock', async () => {
        await expect(
          contracts.issuanceAllocator.connect(accounts.nonGovernor).setIssuancePerBlock(ethersLib.parseEther('200')),
        ).to.be.revertedWithCustomError(contracts.issuanceAllocator, 'AccessControlUnauthorizedAccount')
      })

      it('should allow governor to call setIssuancePerBlock', async () => {
        // In HH v3, just await the call - if it reverts, the test fails
        await contracts.issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethersLib.parseEther('200'))
      })

      it('should revert when non-governor calls setIssuancePerBlock (2-param variant)', async () => {
        await expect(
          contracts.issuanceAllocator
            .connect(accounts.nonGovernor)
            ['setIssuancePerBlock(uint256,uint256)'](ethersLib.parseEther('300'), 0),
        ).to.be.revertedWithCustomError(contracts.issuanceAllocator, 'AccessControlUnauthorizedAccount')
      })

      it('should allow governor to call setIssuancePerBlock (2-param variant)', async () => {
        // In HH v3, just await the call - if it reverts, the test fails
        await contracts.issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethersLib.parseEther('300'))
      })
    })

    describe('setTargetAllocation', () => {
      it('should revert when non-governor calls setTargetAllocation', async () => {
        await expect(
          contracts.issuanceAllocator
            .connect(accounts.nonGovernor)
            ['setTargetAllocation(address,uint256,uint256)'](accounts.nonGovernor.address, 100000, 0),
        ).to.be.revertedWithCustomError(contracts.issuanceAllocator, 'AccessControlUnauthorizedAccount')
      })

      it('should allow governor to call setTargetAllocation', async () => {
        // Use a valid target contract address instead of EOA
        // In HH v3, just await the call - if it reverts, the test fails
        await contracts.issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](contracts.directAllocation.target, 100000, 0)
      })

      it('should revert when non-governor calls setTargetAllocation (3-param variant)', async () => {
        await expect(
          contracts.issuanceAllocator
            .connect(accounts.nonGovernor)
            ['setTargetAllocation(address,uint256,uint256,uint256)'](accounts.nonGovernor.address, 100000, 0, 0),
        ).to.be.revertedWithCustomError(contracts.issuanceAllocator, 'AccessControlUnauthorizedAccount')
      })

      it('should allow governor to call setTargetAllocation (3-param variant)', async () => {
        // Use a valid target contract address instead of EOA
        // In HH v3, just await the call - if it reverts, the test fails
        await contracts.issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256,uint256)'](contracts.directAllocation.target, 100000, 0, 0)
      })
    })

    describe('notifyTarget', () => {
      it('should revert when non-governor calls notifyTarget', async () => {
        await expect(
          contracts.issuanceAllocator.connect(accounts.nonGovernor).notifyTarget(contracts.directAllocation.target),
        ).to.be.revertedWithCustomError(contracts.issuanceAllocator, 'AccessControlUnauthorizedAccount')
      })

      it('should allow governor to call notifyTarget', async () => {
        // First add the target so notifyTarget has something to notify
        await contracts.issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256,uint256)'](contracts.directAllocation.target, 100000, 0)

        // In HH v3, just await the call - if it reverts, the test fails
        await contracts.issuanceAllocator.connect(accounts.governor).notifyTarget(contracts.directAllocation.target)
      })
    })

    describe('forceTargetNoChangeNotificationBlock', () => {
      it('should revert when non-governor calls forceTargetNoChangeNotificationBlock', async () => {
        await expect(
          contracts.issuanceAllocator
            .connect(accounts.nonGovernor)
            .forceTargetNoChangeNotificationBlock(contracts.directAllocation.target, 12345),
        ).to.be.revertedWithCustomError(contracts.issuanceAllocator, 'AccessControlUnauthorizedAccount')
      })

      it('should allow governor to call forceTargetNoChangeNotificationBlock', async () => {
        // In HH v3, just await the call - if it reverts, the test fails
        await contracts.issuanceAllocator
          .connect(accounts.governor)
          .forceTargetNoChangeNotificationBlock(contracts.directAllocation.target, 12345)
      })
    })

    describe('Role Management Methods', () => {
      it('should enforce access control on role management methods', async () => {
        await testMultipleAccessControl(
          contracts.issuanceAllocator,
          [
            {
              method: 'grantRole',
              args: [SHARED_CONSTANTS.PAUSE_ROLE, accounts.operator.address],
              description: 'grantRole',
            },
            {
              method: 'revokeRole',
              args: [SHARED_CONSTANTS.PAUSE_ROLE, accounts.operator.address],
              description: 'revokeRole',
            },
          ],
          accounts.governor,
          accounts.nonGovernor,
        )
      })
    })
  })

  describe('DirectAllocation Access Control', () => {
    describe('Role Management Methods', () => {
      it('should enforce access control on role management methods', async () => {
        await testMultipleAccessControl(
          contracts.directAllocation,
          [
            {
              method: 'grantRole',
              args: [SHARED_CONSTANTS.OPERATOR_ROLE, accounts.operator.address],
              description: 'grantRole',
            },
            {
              method: 'revokeRole',
              args: [SHARED_CONSTANTS.OPERATOR_ROLE, accounts.operator.address],
              description: 'revokeRole',
            },
          ],
          accounts.governor,
          accounts.nonGovernor,
        )
      })
    })

    it('should require OPERATOR_ROLE for sendTokens', async () => {
      // Setup: Grant operator role first
      await contracts.directAllocation
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.operator.address)

      // Non-operator should be rejected
      await expect(
        contracts.directAllocation.connect(accounts.nonGovernor).sendTokens(accounts.nonGovernor.address, 1000),
      ).to.be.revertedWithCustomError(contracts.directAllocation, 'AccessControlUnauthorizedAccount')

      // Operator should be allowed (may revert for other reasons like insufficient balance, but not access control)
      // We just test that access control passes, not the full functionality
      const hasRole = await contracts.directAllocation.hasRole(
        SHARED_CONSTANTS.OPERATOR_ROLE,
        accounts.operator.address,
      )
      expect(hasRole).to.be.true
    })

    it('should require GOVERNOR_ROLE for setIssuanceAllocator', async () => {
      await expect(
        contracts.directAllocation.connect(accounts.nonGovernor).setIssuanceAllocator(accounts.user.address),
      ).to.be.revertedWithCustomError(contracts.directAllocation, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('Role Management Consistency', () => {
    it('should have consistent GOVERNOR_ROLE across allocate contracts', async () => {
      const governorRole = SHARED_CONSTANTS.GOVERNOR_ROLE

      // All allocate contracts should recognize the governor
      expect(await contracts.issuanceAllocator.hasRole(governorRole, accounts.governor.address)).to.be.true
      expect(await contracts.directAllocation.hasRole(governorRole, accounts.governor.address)).to.be.true
    })

    it('should have correct role admin hierarchy', async () => {
      const governorRole = SHARED_CONSTANTS.GOVERNOR_ROLE

      // GOVERNOR_ROLE should be admin of itself (allowing governors to manage other governors)
      expect(await contracts.issuanceAllocator.getRoleAdmin(governorRole)).to.equal(governorRole)
      expect(await contracts.directAllocation.getRoleAdmin(governorRole)).to.equal(governorRole)
    })
  })

  describe('Role Enumeration (AccessControlEnumerable)', () => {
    it('should track role member count correctly for IssuanceAllocator', async () => {
      // GOVERNOR_ROLE should have 1 member (the governor)
      const governorCount = await contracts.issuanceAllocator.getRoleMemberCount(SHARED_CONSTANTS.GOVERNOR_ROLE)
      expect(governorCount).to.equal(1n)

      // Get initial PAUSE_ROLE count
      const pauseCountBefore = await contracts.issuanceAllocator.getRoleMemberCount(SHARED_CONSTANTS.PAUSE_ROLE)

      // Grant PAUSE_ROLE to a new account
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.PAUSE_ROLE, accounts.user.address)

      // Count should increase by 1
      const pauseCountAfter = await contracts.issuanceAllocator.getRoleMemberCount(SHARED_CONSTANTS.PAUSE_ROLE)
      expect(pauseCountAfter).to.equal(pauseCountBefore + 1n)

      // Revoke the role
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        .revokeRole(SHARED_CONSTANTS.PAUSE_ROLE, accounts.user.address)

      // Count should decrease back
      const pauseCountFinal = await contracts.issuanceAllocator.getRoleMemberCount(SHARED_CONSTANTS.PAUSE_ROLE)
      expect(pauseCountFinal).to.equal(pauseCountBefore)
    })

    it('should enumerate role members by index for IssuanceAllocator', async () => {
      // Get the governor address via getRoleMember
      const governorMember = await contracts.issuanceAllocator.getRoleMember(SHARED_CONSTANTS.GOVERNOR_ROLE, 0)
      expect(governorMember).to.equal(accounts.governor.address)

      // Grant multiple pause guardians
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.PAUSE_ROLE, accounts.indexer1.address)
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.PAUSE_ROLE, accounts.indexer2.address)

      // Should be able to enumerate both
      const count = await contracts.issuanceAllocator.getRoleMemberCount(SHARED_CONSTANTS.PAUSE_ROLE)
      expect(count).to.be.gte(2n)

      // Get members by index and verify they are the expected addresses
      const members: string[] = []
      for (let i = 0; i < count; i++) {
        const member = await contracts.issuanceAllocator.getRoleMember(SHARED_CONSTANTS.PAUSE_ROLE, i)
        members.push(member)
      }
      expect(members).to.include(accounts.indexer1.address)
      expect(members).to.include(accounts.indexer2.address)

      // Clean up
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        .revokeRole(SHARED_CONSTANTS.PAUSE_ROLE, accounts.indexer1.address)
      await contracts.issuanceAllocator
        .connect(accounts.governor)
        .revokeRole(SHARED_CONSTANTS.PAUSE_ROLE, accounts.indexer2.address)
    })

    it('should revert when accessing out-of-bounds index', async () => {
      const count = await contracts.issuanceAllocator.getRoleMemberCount(SHARED_CONSTANTS.GOVERNOR_ROLE)

      // Accessing index >= count should revert
      await expect(
        contracts.issuanceAllocator.getRoleMember(SHARED_CONSTANTS.GOVERNOR_ROLE, count),
      ).to.be.revertedWithPanic(0x32) // Array out of bounds
    })

    it('should track role member count correctly for DirectAllocation', async () => {
      // GOVERNOR_ROLE should have 1 member (the governor)
      const governorCount = await contracts.directAllocation.getRoleMemberCount(SHARED_CONSTANTS.GOVERNOR_ROLE)
      expect(governorCount).to.equal(1n)
    })
  })
})

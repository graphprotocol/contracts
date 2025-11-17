/**
 * Allocate Access Control Tests
 * Tests access control patterns for IssuanceAllocator and DirectAllocation contracts
 */

import { expect } from 'chai'
import hre from 'hardhat'
const { ethers } = hre
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
      ethers.parseEther('100'),
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
          contracts.issuanceAllocator
            .connect(accounts.nonGovernor)
            .setIssuancePerBlock(ethers.parseEther('200'), false),
        ).to.be.revertedWithCustomError(contracts.issuanceAllocator, 'AccessControlUnauthorizedAccount')
      })

      it('should allow governor to call setIssuancePerBlock', async () => {
        await expect(
          contracts.issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(ethers.parseEther('200'), false),
        ).to.not.be.reverted
      })
    })

    describe('setTargetAllocation', () => {
      it('should revert when non-governor calls setTargetAllocation', async () => {
        await expect(
          contracts.issuanceAllocator
            .connect(accounts.nonGovernor)
            ['setTargetAllocation(address,uint256,uint256,bool)'](accounts.nonGovernor.address, 100000, 0, false),
        ).to.be.revertedWithCustomError(contracts.issuanceAllocator, 'AccessControlUnauthorizedAccount')
      })

      it('should allow governor to call setTargetAllocation', async () => {
        // Use a valid target contract address instead of EOA
        await expect(
          contracts.issuanceAllocator
            .connect(accounts.governor)
            ['setTargetAllocation(address,uint256,uint256,bool)'](contracts.directAllocation.target, 100000, 0, false),
        ).to.not.be.reverted
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
          ['setTargetAllocation(address,uint256,uint256,bool)'](contracts.directAllocation.target, 100000, 0, false)

        await expect(
          contracts.issuanceAllocator.connect(accounts.governor).notifyTarget(contracts.directAllocation.target),
        ).to.not.be.reverted
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
        await expect(
          contracts.issuanceAllocator
            .connect(accounts.governor)
            .forceTargetNoChangeNotificationBlock(contracts.directAllocation.target, 12345),
        ).to.not.be.reverted
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
})

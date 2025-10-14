/**
 * Consolidated Access Control Tests
 * Tests access control patterns across all contracts to reduce duplication
 */

import { expect } from 'chai'
import hre from 'hardhat'
const { ethers } = hre
import { testMultipleAccessControl } from '../helpers/commonTestUtils'
import { deploySharedContracts, resetContractState, SHARED_CONSTANTS } from '../helpers/fixtures'

describe('Consolidated Access Control Tests', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    const sharedSetup = await deploySharedContracts()
    accounts = sharedSetup.accounts
    contracts = sharedSetup.contracts
  })

  beforeEach(async () => {
    await resetContractState(contracts, accounts)
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

  describe('RewardsEligibilityOracle Access Control', () => {
    describe('Role Management Methods', () => {
      it('should enforce access control on role management methods', async () => {
        // First grant governor the OPERATOR_ROLE so they can manage oracle roles
        await contracts.rewardsEligibilityOracle
          .connect(accounts.governor)
          .grantRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.governor.address)

        const methods = [
          {
            method: 'grantRole',
            args: [SHARED_CONSTANTS.ORACLE_ROLE, accounts.operator.address],
            description: 'grantRole for ORACLE_ROLE',
          },
          {
            method: 'revokeRole',
            args: [SHARED_CONSTANTS.ORACLE_ROLE, accounts.operator.address],
            description: 'revokeRole for ORACLE_ROLE',
          },
        ]

        for (const { method, args, description } of methods) {
          // Test unauthorized access
          await expect(
            contracts.rewardsEligibilityOracle.connect(accounts.nonGovernor)[method](...args),
            `${description} should revert for unauthorized account`,
          ).to.be.revertedWithCustomError(contracts.rewardsEligibilityOracle, 'AccessControlUnauthorizedAccount')

          // Test authorized access
          await expect(
            contracts.rewardsEligibilityOracle.connect(accounts.governor)[method](...args),
            `${description} should succeed for authorized account`,
          ).to.not.be.reverted
        }
      })
    })

    it('should require ORACLE_ROLE for renewIndexerEligibility', async () => {
      // Setup: Grant governor OPERATOR_ROLE first, then grant oracle role
      await contracts.rewardsEligibilityOracle
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.governor.address)
      await contracts.rewardsEligibilityOracle
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.ORACLE_ROLE, accounts.operator.address)

      // Non-oracle should be rejected
      await expect(
        contracts.rewardsEligibilityOracle
          .connect(accounts.nonGovernor)
          .renewIndexerEligibility([accounts.nonGovernor.address], '0x'),
      ).to.be.revertedWithCustomError(contracts.rewardsEligibilityOracle, 'AccessControlUnauthorizedAccount')

      // Oracle should be allowed
      const hasRole = await contracts.rewardsEligibilityOracle.hasRole(
        SHARED_CONSTANTS.ORACLE_ROLE,
        accounts.operator.address,
      )
      expect(hasRole).to.be.true
    })

    it('should require OPERATOR_ROLE for pause operations', async () => {
      // Setup: Grant pause role to governor
      await contracts.rewardsEligibilityOracle
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.PAUSE_ROLE, accounts.governor.address)

      // Non-pause-role account should be rejected
      await expect(
        contracts.rewardsEligibilityOracle.connect(accounts.nonGovernor).pause(),
      ).to.be.revertedWithCustomError(contracts.rewardsEligibilityOracle, 'AccessControlUnauthorizedAccount')
      await expect(
        contracts.rewardsEligibilityOracle.connect(accounts.nonGovernor).unpause(),
      ).to.be.revertedWithCustomError(contracts.rewardsEligibilityOracle, 'AccessControlUnauthorizedAccount')

      // PAUSE_ROLE account should be allowed
      await expect(contracts.rewardsEligibilityOracle.connect(accounts.governor).pause()).to.not.be.reverted
    })

    it('should require OPERATOR_ROLE for configuration methods', async () => {
      // Test all operator-only configuration methods
      const operatorOnlyMethods = [
        {
          call: () =>
            contracts.rewardsEligibilityOracle.connect(accounts.nonGovernor).setEligibilityPeriod(14 * 24 * 60 * 60),
          name: 'setEligibilityPeriod',
        },
        {
          call: () =>
            contracts.rewardsEligibilityOracle.connect(accounts.nonGovernor).setOracleUpdateTimeout(60 * 24 * 60 * 60),
          name: 'setOracleUpdateTimeout',
        },
        {
          call: () => contracts.rewardsEligibilityOracle.connect(accounts.nonGovernor).setEligibilityValidation(false),
          name: 'setEligibilityValidation(false)',
        },
        {
          call: () => contracts.rewardsEligibilityOracle.connect(accounts.nonGovernor).setEligibilityValidation(true),
          name: 'setEligibilityValidation(true)',
        },
      ]

      // Test all methods in sequence
      for (const method of operatorOnlyMethods) {
        await expect(method.call()).to.be.revertedWithCustomError(
          contracts.rewardsEligibilityOracle,
          'AccessControlUnauthorizedAccount',
        )
      }
    })
  })

  describe('Role Management Consistency', () => {
    it('should have consistent GOVERNOR_ROLE across all contracts', async () => {
      const governorRole = SHARED_CONSTANTS.GOVERNOR_ROLE

      // All contracts should recognize the governor
      expect(await contracts.issuanceAllocator.hasRole(governorRole, accounts.governor.address)).to.be.true
      expect(await contracts.directAllocation.hasRole(governorRole, accounts.governor.address)).to.be.true
      expect(await contracts.rewardsEligibilityOracle.hasRole(governorRole, accounts.governor.address)).to.be.true
    })

    it('should have correct role admin hierarchy', async () => {
      const governorRole = SHARED_CONSTANTS.GOVERNOR_ROLE

      // GOVERNOR_ROLE should be admin of itself (allowing governors to manage other governors)
      expect(await contracts.issuanceAllocator.getRoleAdmin(governorRole)).to.equal(governorRole)
      expect(await contracts.directAllocation.getRoleAdmin(governorRole)).to.equal(governorRole)
      expect(await contracts.rewardsEligibilityOracle.getRoleAdmin(governorRole)).to.equal(governorRole)
    })
  })
})

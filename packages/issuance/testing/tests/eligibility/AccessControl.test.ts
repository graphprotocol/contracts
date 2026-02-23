/**
 * Eligibility Access Control Tests
 * Tests access control patterns for RewardsEligibilityOracle contract
 */

import { expect } from 'chai'

import { deployTestGraphToken, getTestAccounts, SHARED_CONSTANTS } from '../common/fixtures'
import { deployRewardsEligibilityOracle } from './fixtures'

describe('Eligibility Access Control Tests', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy eligibility contracts
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()
    const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

    contracts = {
      graphToken,
      rewardsEligibilityOracle,
    }
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

          // Test authorized access - should succeed without reverting
          await contracts.rewardsEligibilityOracle.connect(accounts.governor)[method](...args)
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

      // PAUSE_ROLE account should be allowed to pause
      await contracts.rewardsEligibilityOracle.connect(accounts.governor).pause()

      // PAUSE_ROLE account should be allowed to unpause
      await contracts.rewardsEligibilityOracle.connect(accounts.governor).unpause()
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
    it('should have consistent GOVERNOR_ROLE for eligibility contracts', async () => {
      const governorRole = SHARED_CONSTANTS.GOVERNOR_ROLE

      // RewardsEligibilityOracle should recognize the governor
      expect(await contracts.rewardsEligibilityOracle.hasRole(governorRole, accounts.governor.address)).to.be.true
    })

    it('should have correct role admin hierarchy', async () => {
      const governorRole = SHARED_CONSTANTS.GOVERNOR_ROLE

      // GOVERNOR_ROLE should be admin of itself (allowing governors to manage other governors)
      expect(await contracts.rewardsEligibilityOracle.getRoleAdmin(governorRole)).to.equal(governorRole)
    })
  })

  describe('Role Enumeration (AccessControlEnumerable)', () => {
    it('should track role member count correctly', async () => {
      // GOVERNOR_ROLE should have 1 member (the governor)
      const governorCount = await contracts.rewardsEligibilityOracle.getRoleMemberCount(SHARED_CONSTANTS.GOVERNOR_ROLE)
      expect(governorCount).to.equal(1n)

      // Get initial OPERATOR_ROLE count
      const operatorCountBefore = await contracts.rewardsEligibilityOracle.getRoleMemberCount(
        SHARED_CONSTANTS.OPERATOR_ROLE,
      )

      // Grant OPERATOR_ROLE to a new account
      await contracts.rewardsEligibilityOracle
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.user.address)

      // Count should increase by 1
      const operatorCountAfter = await contracts.rewardsEligibilityOracle.getRoleMemberCount(
        SHARED_CONSTANTS.OPERATOR_ROLE,
      )
      expect(operatorCountAfter).to.equal(operatorCountBefore + 1n)

      // Revoke the role
      await contracts.rewardsEligibilityOracle
        .connect(accounts.governor)
        .revokeRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.user.address)

      // Count should decrease back
      const operatorCountFinal = await contracts.rewardsEligibilityOracle.getRoleMemberCount(
        SHARED_CONSTANTS.OPERATOR_ROLE,
      )
      expect(operatorCountFinal).to.equal(operatorCountBefore)
    })

    it('should enumerate role members by index', async () => {
      // Get the governor address via getRoleMember
      const governorMember = await contracts.rewardsEligibilityOracle.getRoleMember(SHARED_CONSTANTS.GOVERNOR_ROLE, 0)
      expect(governorMember).to.equal(accounts.governor.address)

      // Grant multiple operators
      await contracts.rewardsEligibilityOracle
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.indexer1.address)
      await contracts.rewardsEligibilityOracle
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.indexer2.address)

      // Should be able to enumerate both
      const count = await contracts.rewardsEligibilityOracle.getRoleMemberCount(SHARED_CONSTANTS.OPERATOR_ROLE)
      expect(count).to.be.gte(2n)

      // Get members by index and verify they are the expected addresses
      const members: string[] = []
      for (let i = 0; i < count; i++) {
        const member = await contracts.rewardsEligibilityOracle.getRoleMember(SHARED_CONSTANTS.OPERATOR_ROLE, i)
        members.push(member)
      }
      expect(members).to.include(accounts.indexer1.address)
      expect(members).to.include(accounts.indexer2.address)

      // Clean up
      await contracts.rewardsEligibilityOracle
        .connect(accounts.governor)
        .revokeRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.indexer1.address)
      await contracts.rewardsEligibilityOracle
        .connect(accounts.governor)
        .revokeRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.indexer2.address)
    })

    it('should revert when accessing out-of-bounds index', async () => {
      const count = await contracts.rewardsEligibilityOracle.getRoleMemberCount(SHARED_CONSTANTS.GOVERNOR_ROLE)

      // Accessing index >= count should revert
      await expect(
        contracts.rewardsEligibilityOracle.getRoleMember(SHARED_CONSTANTS.GOVERNOR_ROLE, count),
      ).to.be.revertedWithPanic(0x32) // Array out of bounds
    })
  })
})

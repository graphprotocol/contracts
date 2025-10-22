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

      // PAUSE_ROLE account should be allowed to pause
      await expect(contracts.rewardsEligibilityOracle.connect(accounts.governor).pause()).to.not.be.reverted

      // PAUSE_ROLE account should be allowed to unpause
      await expect(contracts.rewardsEligibilityOracle.connect(accounts.governor).unpause()).to.not.be.reverted
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
})

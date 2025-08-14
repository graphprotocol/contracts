/* eslint-disable @typescript-eslint/no-explicit-any */
/**
 * Consolidated Access Control Tests
 * Tests access control patterns across all contracts to reduce duplication
 */

const { expect } = require('chai')
const { deploySharedContracts, resetContractState, SHARED_CONSTANTS } = require('../helpers/sharedFixtures')

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

  describe('ServiceQualityOracle Access Control', () => {
    describe('Role Management Methods', () => {
      it('should enforce access control on role management methods', async () => {
        // First grant governor the OPERATOR_ROLE so they can manage oracle roles
        await contracts.serviceQualityOracle
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
            contracts.serviceQualityOracle.connect(accounts.nonGovernor)[method](...args),
            `${description} should revert for unauthorized account`,
          ).to.be.revertedWithCustomError(contracts.serviceQualityOracle, 'AccessControlUnauthorizedAccount')

          // Test authorized access
          await expect(
            contracts.serviceQualityOracle.connect(accounts.governor)[method](...args),
            `${description} should succeed for authorized account`,
          ).to.not.be.reverted
        }
      })
    })

    it('should require ORACLE_ROLE for allowIndexers', async () => {
      // Setup: Grant governor OPERATOR_ROLE first, then grant oracle role
      await contracts.serviceQualityOracle
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.OPERATOR_ROLE, accounts.governor.address)
      await contracts.serviceQualityOracle
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.ORACLE_ROLE, accounts.operator.address)

      // Non-oracle should be rejected
      await expect(
        contracts.serviceQualityOracle
          .connect(accounts.nonGovernor)
          .allowIndexers([accounts.nonGovernor.address], '0x'),
      ).to.be.revertedWithCustomError(contracts.serviceQualityOracle, 'AccessControlUnauthorizedAccount')

      // Oracle should be allowed
      const hasRole = await contracts.serviceQualityOracle.hasRole(
        SHARED_CONSTANTS.ORACLE_ROLE,
        accounts.operator.address,
      )
      expect(hasRole).to.be.true
    })

    it('should require OPERATOR_ROLE for pause operations', async () => {
      // Setup: Grant pause role to governor
      await contracts.serviceQualityOracle
        .connect(accounts.governor)
        .grantRole(SHARED_CONSTANTS.PAUSE_ROLE, accounts.governor.address)

      // Non-pause-role account should be rejected
      await expect(contracts.serviceQualityOracle.connect(accounts.nonGovernor).pause()).to.be.revertedWithCustomError(
        contracts.serviceQualityOracle,
        'AccessControlUnauthorizedAccount',
      )
      await expect(
        contracts.serviceQualityOracle.connect(accounts.nonGovernor).unpause(),
      ).to.be.revertedWithCustomError(contracts.serviceQualityOracle, 'AccessControlUnauthorizedAccount')

      // Pause role account should be allowed
      await expect(contracts.serviceQualityOracle.connect(accounts.governor).pause()).to.not.be.reverted
    })

    it('should require OPERATOR_ROLE for configuration methods', async () => {
      // Test all operator-only configuration methods
      const operatorOnlyMethods = [
        {
          call: () => contracts.serviceQualityOracle.connect(accounts.nonGovernor).setAllowedPeriod(14 * 24 * 60 * 60),
          name: 'setAllowedPeriod',
        },
        {
          call: () =>
            contracts.serviceQualityOracle.connect(accounts.nonGovernor).setOracleUpdateTimeout(60 * 24 * 60 * 60),
          name: 'setOracleUpdateTimeout',
        },
        {
          call: () => contracts.serviceQualityOracle.connect(accounts.nonGovernor).setQualityChecking(false),
          name: 'setQualityChecking(false)',
        },
        {
          call: () => contracts.serviceQualityOracle.connect(accounts.nonGovernor).setQualityChecking(true),
          name: 'setQualityChecking(true)',
        },
      ]

      // Test all methods in sequence
      for (const method of operatorOnlyMethods) {
        await expect(method.call()).to.be.revertedWithCustomError(
          contracts.serviceQualityOracle,
          'AccessControlUnauthorizedAccount',
        )
      }
    })
  })

  describe('Role Management Consistency', () => {
    it('should have consistent GOVERNOR_ROLE across all contracts', async () => {
      const governorRole = SHARED_CONSTANTS.GOVERNOR_ROLE

      // All contracts should recognize the governor
      expect(await contracts.serviceQualityOracle.hasRole(governorRole, accounts.governor.address)).to.be.true
    })

    it('should have correct role admin hierarchy', async () => {
      const governorRole = SHARED_CONSTANTS.GOVERNOR_ROLE

      // GOVERNOR_ROLE should be admin of itself (allowing governors to manage other governors)
      expect(await contracts.serviceQualityOracle.getRoleAdmin(governorRole)).to.equal(governorRole)
    })
  })
})

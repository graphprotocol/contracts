import { time } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import { ethers, upgrades } from 'hardhat'

import { deployRewardsEligibilityOracle, deployTestGraphToken, getTestAccounts } from './helpers/fixtures'
import { SHARED_CONSTANTS } from './helpers/sharedFixtures'

// Role constants
const GOVERNOR_ROLE = SHARED_CONSTANTS.GOVERNOR_ROLE
const ORACLE_ROLE = SHARED_CONSTANTS.ORACLE_ROLE
const OPERATOR_ROLE = SHARED_CONSTANTS.OPERATOR_ROLE

describe('RewardsEligibilityOracle', () => {
  // Common variables
  let accounts
  let sharedContracts

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy shared contracts once
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()
    const rewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)
    const rewardsEligibilityOracleAddress = await rewardsEligibilityOracle.getAddress()

    sharedContracts = {
      graphToken,
      rewardsEligibilityOracle,
      addresses: {
        graphToken: graphTokenAddress,
        rewardsEligibilityOracle: rewardsEligibilityOracleAddress,
      },
    }
  })

  // Fast state reset function
  async function resetOracleState() {
    if (!sharedContracts) return

    const { rewardsEligibilityOracle } = sharedContracts

    // Remove oracle roles from all accounts
    try {
      for (const account of [accounts.operator, accounts.user, accounts.nonGovernor]) {
        if (await rewardsEligibilityOracle.hasRole(ORACLE_ROLE, account.address)) {
          await rewardsEligibilityOracle.connect(accounts.governor).revokeRole(ORACLE_ROLE, account.address)
        }
        if (await rewardsEligibilityOracle.hasRole(OPERATOR_ROLE, account.address)) {
          await rewardsEligibilityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, account.address)
        }
      }

      // Remove operator role from governor if present
      if (await rewardsEligibilityOracle.hasRole(OPERATOR_ROLE, accounts.governor.address)) {
        await rewardsEligibilityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, accounts.governor.address)
      }
    } catch {
      // Ignore role management errors during reset
    }

    // Reset to default values
    try {
      // Reset eligibility period to default (14 days)
      const defaultEligibilityPeriod = 14 * 24 * 60 * 60
      const currentEligibilityPeriod = await rewardsEligibilityOracle.getEligibilityPeriod()
      if (currentEligibilityPeriod !== BigInt(defaultEligibilityPeriod)) {
        await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.governor.address)
        await rewardsEligibilityOracle.connect(accounts.governor).setEligibilityPeriod(defaultEligibilityPeriod)
        await rewardsEligibilityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, accounts.governor.address)
      }

      // Reset eligibility validation to disabled
      if (await rewardsEligibilityOracle.getEligibilityValidation()) {
        await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.governor.address)
        await rewardsEligibilityOracle.connect(accounts.governor).setEligibilityValidation(false)
        await rewardsEligibilityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, accounts.governor.address)
      }

      // Reset oracle update timeout to default (7 days)
      const defaultTimeout = 7 * 24 * 60 * 60
      const currentTimeout = await rewardsEligibilityOracle.getOracleUpdateTimeout()
      if (currentTimeout !== BigInt(defaultTimeout)) {
        await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.governor.address)
        await rewardsEligibilityOracle.connect(accounts.governor).setOracleUpdateTimeout(defaultTimeout)
        await rewardsEligibilityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, accounts.governor.address)
      }
    } catch {
      // Ignore reset errors
    }
  }

  beforeEach(async () => {
    if (!accounts) {
      accounts = await getTestAccounts()
    }
    await resetOracleState()
  })

  describe('Construction', () => {
    it('should revert when constructed with zero GraphToken address', async () => {
      const RewardsEligibilityOracleFactory = await ethers.getContractFactory('RewardsEligibilityOracle')
      await expect(RewardsEligibilityOracleFactory.deploy(ethers.ZeroAddress)).to.be.revertedWithCustomError(
        RewardsEligibilityOracleFactory,
        'GraphTokenCannotBeZeroAddress',
      )
    })

    it('should revert when initialized with zero governor address', async () => {
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()

      // Try to deploy proxy with zero governor address - this should hit the BaseUpgradeable check
      const RewardsEligibilityOracleFactory = await ethers.getContractFactory('RewardsEligibilityOracle')
      await expect(
        upgrades.deployProxy(RewardsEligibilityOracleFactory, [ethers.ZeroAddress], {
          constructorArgs: [graphTokenAddress],
          initializer: 'initialize',
        }),
      ).to.be.revertedWithCustomError(RewardsEligibilityOracleFactory, 'GovernorCannotBeZeroAddress')
    })
  })

  describe('Initialization', () => {
    it('should set the governor role correctly', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      expect(await rewardsEligibilityOracle.hasRole(GOVERNOR_ROLE, accounts.governor.address)).to.be.true
    })

    it('should not set oracle role to anyone initially', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      expect(await rewardsEligibilityOracle.hasRole(ORACLE_ROLE, accounts.operator.address)).to.be.false
    })

    it('should set default eligibility period to 14 days', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      expect(await rewardsEligibilityOracle.getEligibilityPeriod()).to.equal(14 * 24 * 60 * 60) // 14 days in seconds
    })

    it('should set eligibility validation to disabled by default', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      expect(await rewardsEligibilityOracle.getEligibilityValidation()).to.be.false
    })

    it('should set default oracle update timeout to 7 days', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      expect(await rewardsEligibilityOracle.getOracleUpdateTimeout()).to.equal(7 * 24 * 60 * 60) // 7 days in seconds
    })

    it('should initialize lastOracleUpdateTime to 0', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      expect(await rewardsEligibilityOracle.getLastOracleUpdateTime()).to.equal(0)
    })

    it('should revert when initialize is called more than once', async () => {
      const { rewardsEligibilityOracle } = sharedContracts

      // Try to call initialize again
      await expect(rewardsEligibilityOracle.initialize(accounts.governor.address)).to.be.revertedWithCustomError(
        rewardsEligibilityOracle,
        'InvalidInitialization',
      )
    })
  })

  describe('Oracle Management', () => {
    it('should allow operator to grant oracle role', async () => {
      const { rewardsEligibilityOracle } = sharedContracts

      // Grant operator role to the operator account
      await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)

      // Operator grants oracle role
      await rewardsEligibilityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.user.address)
      expect(await rewardsEligibilityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.true
    })

    it('should allow operator to revoke oracle role', async () => {
      const { rewardsEligibilityOracle } = sharedContracts

      // Grant operator role to the operator account
      await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)

      // Grant oracle role first
      await rewardsEligibilityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.user.address)
      expect(await rewardsEligibilityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.true

      // Revoke role
      await rewardsEligibilityOracle.connect(accounts.operator).revokeRole(ORACLE_ROLE, accounts.user.address)
      expect(await rewardsEligibilityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.false
    })

    // Access control tests moved to consolidated/AccessControl.test.ts
  })

  describe('Operator Functions', () => {
    beforeEach(async () => {
      const { rewardsEligibilityOracle } = sharedContracts

      // Grant operator role to the operator account
      await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
    })

    it('should allow operator to set eligibility period', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      const newEligibilityPeriod = 14 * 24 * 60 * 60 // 14 days

      // Set eligibility period
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityPeriod(newEligibilityPeriod)

      // Check if eligibility period was updated
      expect(await rewardsEligibilityOracle.getEligibilityPeriod()).to.equal(newEligibilityPeriod)
    })

    it('should handle idempotent operations correctly', async () => {
      const { rewardsEligibilityOracle } = sharedContracts

      // Test setting same eligibility period
      const currentEligibilityPeriod = await rewardsEligibilityOracle.getEligibilityPeriod()
      let result = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .setEligibilityPeriod.staticCall(currentEligibilityPeriod)
      expect(result).to.be.true

      // Verify no event emitted for same value
      let tx = await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityPeriod(currentEligibilityPeriod)
      let receipt = await tx.wait()
      expect(receipt.logs.length).to.equal(0)

      // Test setting new oracle update timeout
      const newTimeout = 60 * 24 * 60 * 60 // 60 days
      await rewardsEligibilityOracle.connect(accounts.operator).setOracleUpdateTimeout(newTimeout)
      expect(await rewardsEligibilityOracle.getOracleUpdateTimeout()).to.equal(newTimeout)

      // Test setting same oracle update timeout
      result = await rewardsEligibilityOracle.connect(accounts.operator).setOracleUpdateTimeout.staticCall(newTimeout)
      expect(result).to.be.true

      // Verify no event emitted for same value
      tx = await rewardsEligibilityOracle.connect(accounts.operator).setOracleUpdateTimeout(newTimeout)
      receipt = await tx.wait()
      expect(receipt.logs.length).to.equal(0)
    })

    it('should allow operator to disable eligibility checking', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      // Disable eligibility validation
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(false)

      // Check if eligibility validation is disabled
      expect(await rewardsEligibilityOracle.getEligibilityValidation()).to.be.false
    })

    it('should allow operator to enable eligibility checking', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      // Disable eligibility validation first
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(false)
      expect(await rewardsEligibilityOracle.getEligibilityValidation()).to.be.false

      // Enable eligibility validation
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(true)

      // Check if eligibility validation is enabled
      expect(await rewardsEligibilityOracle.getEligibilityValidation()).to.be.true
    })

    it('should handle setEligibilityValidation return values and events correctly', async () => {
      const { rewardsEligibilityOracle } = sharedContracts

      // Test 1: Return true when enabling eligibility validation that is already enabled
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(true)
      expect(await rewardsEligibilityOracle.getEligibilityValidation()).to.be.true

      const enableResult = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .setEligibilityValidation.staticCall(true)
      expect(enableResult).to.be.true

      // Test 2: No event emitted when setting to same state (enabled)
      const enableTx = await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(true)
      const enableReceipt = await enableTx.wait()
      expect(enableReceipt.logs.length).to.equal(0)

      // Test 3: Return true when disabling eligibility validation that is already disabled
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(false)
      expect(await rewardsEligibilityOracle.getEligibilityValidation()).to.be.false

      const disableResult = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .setEligibilityValidation.staticCall(false)
      expect(disableResult).to.be.true

      // Test 4: No event emitted when setting to same state (disabled)
      const disableTx = await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(false)
      const disableReceipt = await disableTx.wait()
      expect(disableReceipt.logs.length).to.equal(0)

      // Test 5: Events are emitted when state actually changes
      await expect(rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(true))
        .to.emit(rewardsEligibilityOracle, 'EligibilityValidationUpdated')
        .withArgs(true)

      await expect(rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(false))
        .to.emit(rewardsEligibilityOracle, 'EligibilityValidationUpdated')
        .withArgs(false)
    })

    // Access control tests moved to consolidated/AccessControl.test.ts
    // Event and return value tests consolidated into 'should handle setEligibilityValidation return values and events correctly'
  })

  describe('Indexer Management', () => {
    beforeEach(async () => {
      const { rewardsEligibilityOracle } = sharedContracts

      // Grant operator role to the operator account
      await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)

      // Grant oracle role
      await rewardsEligibilityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)
    })

    it('should allow oracle to allow a single indexer', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      // Renew indexer eligibility using renewIndexerEligibility with a single-element array
      await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.indexer1.address], '0x')

      // Check if indexer is eligible
      expect(await rewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.true

      // Check if allowed timestamp was updated
      const eligibilityRenewalTime = await rewardsEligibilityOracle.getEligibilityRenewalTime(accounts.indexer1.address)
      expect(eligibilityRenewalTime).to.be.gt(0)
    })

    it('should allow oracle to allow multiple indexers', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      // Allow multiple indexers
      const indexers = [accounts.indexer1.address, accounts.indexer2.address]
      await rewardsEligibilityOracle.connect(accounts.operator).renewIndexerEligibility(indexers, '0x')

      // Check if indexers are eligible
      expect(await rewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.true
      expect(await rewardsEligibilityOracle.isEligible(accounts.indexer2.address)).to.be.true

      // Check if allowed timestamps were updated
      const eligibilityRenewalTime1 = await rewardsEligibilityOracle.getEligibilityRenewalTime(
        accounts.indexer1.address,
      )
      const eligibilityRenewalTime2 = await rewardsEligibilityOracle.getEligibilityRenewalTime(
        accounts.indexer2.address,
      )
      expect(eligibilityRenewalTime1).to.be.gt(0)
      expect(eligibilityRenewalTime2).to.be.gt(0)
    })

    it('should not update last renewal timestamp for indexer already renewed in the same block', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      // Renew indexer eligibility first time
      await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.indexer1.address], '0x')

      // Get the timestamp
      const initialEligibilityRenewalTime = await rewardsEligibilityOracle.getEligibilityRenewalTime(
        accounts.indexer1.address,
      )

      // Call renewIndexerEligibility again with the same indexer
      const result = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility.staticCall([accounts.indexer1.address], '0x')

      // The function should return 0 since the indexer was already allowed in this block
      expect(result).to.equal(0)

      // Verify the timestamp hasn't changed
      const finalEligibilityRenewalTime = await rewardsEligibilityOracle.getEligibilityRenewalTime(
        accounts.indexer1.address,
      )
      expect(finalEligibilityRenewalTime).to.equal(initialEligibilityRenewalTime)

      // Mine a new block
      await ethers.provider.send('evm_mine', [])

      // Now try again in a new block - it should return 1
      const newBlockResult = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility.staticCall([accounts.indexer1.address], '0x')

      // The function should return 1 since we're in a new block
      expect(newBlockResult).to.equal(1)
    })

    it('should revert when non-oracle tries to allow a single indexer', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      await expect(
        rewardsEligibilityOracle
          .connect(accounts.nonGovernor)
          .renewIndexerEligibility([accounts.indexer1.address], '0x'),
      ).to.be.revertedWithCustomError(rewardsEligibilityOracle, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when non-oracle tries to allow multiple indexers', async () => {
      const { rewardsEligibilityOracle } = sharedContracts
      const indexers = [accounts.indexer1.address, accounts.indexer2.address]
      await expect(
        rewardsEligibilityOracle.connect(accounts.nonGovernor).renewIndexerEligibility(indexers, '0x'),
      ).to.be.revertedWithCustomError(rewardsEligibilityOracle, 'AccessControlUnauthorizedAccount')
    })

    it('should return correct count for various renewIndexerEligibility scenarios', async () => {
      const { rewardsEligibilityOracle } = sharedContracts

      // Test 1: Single indexer should return 1
      const singleResult = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility.staticCall([accounts.indexer1.address], '0x')
      expect(singleResult).to.equal(1)

      // Test 2: Multiple indexers should return correct count
      const multipleIndexers = [accounts.indexer1.address, accounts.indexer2.address]
      const multipleResult = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility.staticCall(multipleIndexers, '0x')
      expect(multipleResult).to.equal(2)

      // Test 3: Empty array should return 0
      const emptyResult = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility.staticCall([], '0x')
      expect(emptyResult).to.equal(0)

      // Test 4: Array with zero addresses should only count non-zero addresses
      const withZeroAddresses = [accounts.indexer1.address, ethers.ZeroAddress, accounts.indexer2.address]
      const zeroResult = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility.staticCall(withZeroAddresses, '0x')
      expect(zeroResult).to.equal(2)

      // Test 5: Array with duplicates should only count unique indexers
      const withDuplicates = [accounts.indexer1.address, accounts.indexer1.address, accounts.indexer2.address]
      const duplicateResult = await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility.staticCall(withDuplicates, '0x')
      expect(duplicateResult).to.equal(2)
    })
  })

  describe('View Functions', () => {
    // Use shared contracts instead of deploying fresh ones for each test

    it('should return 0 when getting last renewal time for indexer that was never renewed', async () => {
      // Use a fresh deployment to avoid contamination from previous tests
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()
      const freshRewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

      // This should return 0 for a fresh contract
      const lastEligibilityRenewalTime = await freshRewardsEligibilityOracle.getEligibilityRenewalTime(
        accounts.indexer1.address,
      )
      expect(lastEligibilityRenewalTime).to.equal(0)
    })

    it('should return correct last renewal timestamp for renewed indexer', async function () {
      const { rewardsEligibilityOracle } = sharedContracts

      // Grant operator role first (governor can grant operator role)
      await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      // Then operator can grant oracle role (operator is admin of oracle role)
      await rewardsEligibilityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Renew indexer eligibility
      await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.indexer1.address], '0x')

      // Get the last allowed time
      const lastEligibilityRenewalTime = await rewardsEligibilityOracle.getEligibilityRenewalTime(
        accounts.indexer1.address,
      )

      // Get the current block timestamp
      const block = await ethers.provider.getBlock('latest')
      const blockTimestamp = block ? block.timestamp : 0

      // The last allowed time should be close to the current block timestamp
      expect(lastEligibilityRenewalTime).to.be.closeTo(blockTimestamp, 5) // Allow 5 seconds of difference
    })

    it('should correctly report if an indexer is eligible', async function () {
      // Use a fresh deployment to avoid shared state contamination
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()
      const freshRewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

      // Grant necessary roles (follow role hierarchy)
      await freshRewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await freshRewardsEligibilityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable eligibility validation first (since it's disabled by default)
      await freshRewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(true)

      // First, set a non-zero lastOracleUpdateTime to prevent the timeout condition from triggering
      await freshRewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.nonGovernor.address], '0x')

      // Now check if our test indexer is eligible (it shouldn't be)
      expect(await freshRewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.false

      // Renew indexer eligibility
      await freshRewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.indexer1.address], '0x')
      expect(await freshRewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.true
    })

    it('should return true for all indexers when eligibility checking is disabled', async function () {
      // Use a fresh deployment to avoid shared state contamination
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()
      const freshRewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

      // Grant necessary roles (follow role hierarchy)
      await freshRewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await freshRewardsEligibilityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable eligibility validation first (since it's disabled by default)
      await freshRewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(true)

      // First, set a non-zero lastOracleUpdateTime to prevent the timeout condition from triggering
      await freshRewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.nonGovernor.address], '0x')

      // Set a very long oracle update timeout to prevent that condition from triggering
      await freshRewardsEligibilityOracle.connect(accounts.operator).setOracleUpdateTimeout(365 * 24 * 60 * 60) // 1 year

      // Now check if our test indexer is eligible (it shouldn't be)
      expect(await freshRewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.false

      // Disable eligibility validation
      await freshRewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(false)

      // Now indexer should be allowed even without being explicitly allowed
      expect(await freshRewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.true
    })

    it('should return true for all indexers when oracle update timeout is exceeded', async function () {
      // Use a fresh deployment to avoid shared state contamination
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()
      const freshRewardsEligibilityOracle = await deployRewardsEligibilityOracle(graphTokenAddress, accounts.governor)

      // Grant necessary roles (follow role hierarchy)
      await freshRewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await freshRewardsEligibilityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable eligibility validation first (since it's disabled by default)
      await freshRewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(true)

      // First, set a non-zero lastOracleUpdateTime to prevent the initial timeout condition from triggering
      await freshRewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.nonGovernor.address], '0x')

      // Set a very long oracle update timeout initially
      await freshRewardsEligibilityOracle.connect(accounts.operator).setOracleUpdateTimeout(365 * 24 * 60 * 60) // 1 year

      // Now check if our test indexer is eligible (it shouldn't be)
      expect(await freshRewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.false

      // Set a short oracle update timeout
      await freshRewardsEligibilityOracle.connect(accounts.operator).setOracleUpdateTimeout(60) // 1 minute

      // Advance time beyond the timeout
      await time.increase(120) // 2 minutes

      // Now indexer should be allowed even without being explicitly allowed
      expect(await freshRewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.true
    })

    it('should return false for indexer after eligibility period expires', async function () {
      const { rewardsEligibilityOracle } = sharedContracts

      // Grant necessary roles (follow role hierarchy)
      await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await rewardsEligibilityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable eligibility validation first (since it's disabled by default)
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(true)

      // Set a very long oracle update timeout to prevent that condition from triggering
      await rewardsEligibilityOracle.connect(accounts.operator).setOracleUpdateTimeout(365 * 24 * 60 * 60) // 1 year

      // Renew indexer eligibility
      await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.indexer1.address], '0x')
      expect(await rewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.true

      // Set a short eligibility period
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityPeriod(60) // 1 minute

      // Advance time beyond eligibility period
      await time.increase(120) // 2 minutes

      // Now indexer should not be allowed
      expect(await rewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.false
    })

    it('should return true for indexer after re-allowing', async function () {
      const { rewardsEligibilityOracle } = sharedContracts

      // Grant necessary roles
      await rewardsEligibilityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await rewardsEligibilityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable eligibility validation first (since it's disabled by default)
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityValidation(true)

      // Set a very long oracle update timeout to prevent that condition from triggering
      await rewardsEligibilityOracle.connect(accounts.operator).setOracleUpdateTimeout(365 * 24 * 60 * 60) // 1 year

      // Renew indexer eligibility
      await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.indexer1.address], '0x')

      // Set a short eligibility period
      await rewardsEligibilityOracle.connect(accounts.operator).setEligibilityPeriod(60) // 1 minute

      // Advance time beyond eligibility period
      await time.increase(120) // 2 minutes

      // Indexer should not be allowed
      expect(await rewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.false

      // Re-renew indexer eligibility
      await rewardsEligibilityOracle
        .connect(accounts.operator)
        .renewIndexerEligibility([accounts.indexer1.address], '0x')

      // Now indexer should be allowed again
      expect(await rewardsEligibilityOracle.isEligible(accounts.indexer1.address)).to.be.true
    })
  })
})

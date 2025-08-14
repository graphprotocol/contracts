const { time } = require('@nomicfoundation/hardhat-network-helpers')
const { expect } = require('chai')
const { ethers, upgrades } = require('hardhat')

const { getTestAccounts, deployTestGraphToken, deployServiceQualityOracle } = require('./helpers/fixtures')
const { SHARED_CONSTANTS } = require('./helpers/sharedFixtures')

// Role constants
const GOVERNOR_ROLE = SHARED_CONSTANTS.GOVERNOR_ROLE
const ORACLE_ROLE = SHARED_CONSTANTS.ORACLE_ROLE
const OPERATOR_ROLE = SHARED_CONSTANTS.OPERATOR_ROLE

describe('ServiceQualityOracle', () => {
  // Common variables
  let accounts
  let sharedContracts

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy shared contracts once
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()
    const serviceQualityOracle = await deployServiceQualityOracle(graphTokenAddress, accounts.governor)
    const serviceQualityOracleAddress = await serviceQualityOracle.getAddress()

    sharedContracts = {
      graphToken,
      serviceQualityOracle,
      addresses: {
        graphToken: graphTokenAddress,
        serviceQualityOracle: serviceQualityOracleAddress,
      },
    }
  })

  // Fast state reset function
  async function resetOracleState() {
    if (!sharedContracts) return

    const { serviceQualityOracle } = sharedContracts

    // Remove oracle roles from all accounts
    try {
      for (const account of [accounts.operator, accounts.user, accounts.nonGovernor]) {
        if (await serviceQualityOracle.hasRole(ORACLE_ROLE, account.address)) {
          await serviceQualityOracle.connect(accounts.governor).revokeRole(ORACLE_ROLE, account.address)
        }
        if (await serviceQualityOracle.hasRole(OPERATOR_ROLE, account.address)) {
          await serviceQualityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, account.address)
        }
      }

      // Remove operator role from governor if present
      if (await serviceQualityOracle.hasRole(OPERATOR_ROLE, accounts.governor.address)) {
        await serviceQualityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, accounts.governor.address)
      }
    } catch {
      // Ignore role management errors during reset
    }

    // Reset to default values
    try {
      // Reset allowed period to default (14 days)
      const defaultAllowedPeriod = 14 * 24 * 60 * 60
      const currentAllowedPeriod = await serviceQualityOracle.getAllowedPeriod()
      if (currentAllowedPeriod !== BigInt(defaultAllowedPeriod)) {
        await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.governor.address)
        await serviceQualityOracle.connect(accounts.governor).setAllowedPeriod(defaultAllowedPeriod)
        await serviceQualityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, accounts.governor.address)
      }

      // Reset quality checking to inactive
      if (await serviceQualityOracle.isQualityCheckingActive()) {
        await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.governor.address)
        await serviceQualityOracle.connect(accounts.governor).setQualityChecking(false)
        await serviceQualityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, accounts.governor.address)
      }

      // Reset oracle update timeout to default (7 days)
      const defaultTimeout = 7 * 24 * 60 * 60
      const currentTimeout = await serviceQualityOracle.getOracleUpdateTimeout()
      if (currentTimeout !== BigInt(defaultTimeout)) {
        await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.governor.address)
        await serviceQualityOracle.connect(accounts.governor).setOracleUpdateTimeout(defaultTimeout)
        await serviceQualityOracle.connect(accounts.governor).revokeRole(OPERATOR_ROLE, accounts.governor.address)
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

  // // Test fixtures (kept for complex tests that need fresh deployments)
  // async function setupServiceQualityOracle() {
  //   // Deploy test GraphToken
  //   const graphToken = await deployTestGraphToken()
  //   const graphTokenAddress = await graphToken.getAddress()

  //   // Deploy ServiceQualityOracle with proxy
  //   const serviceQualityOracle = await deployServiceQualityOracle(graphTokenAddress, accounts.governor)

  //   return { serviceQualityOracle, graphToken }
  // }

  describe('Construction', () => {
    it('should revert when constructed with zero GraphToken address', async () => {
      const ServiceQualityOracleFactory = await ethers.getContractFactory('ServiceQualityOracle')
      await expect(ServiceQualityOracleFactory.deploy(ethers.ZeroAddress)).to.be.revertedWithCustomError(
        ServiceQualityOracleFactory,
        'GraphTokenCannotBeZeroAddress',
      )
    })

    it('should revert when initialized with zero governor address', async () => {
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()

      // Try to deploy proxy with zero governor address - this should hit the BaseUpgradeable check
      const ServiceQualityOracleFactory = await ethers.getContractFactory('ServiceQualityOracle')
      await expect(
        upgrades.deployProxy(ServiceQualityOracleFactory, [ethers.ZeroAddress], {
          constructorArgs: [graphTokenAddress],
          initializer: 'initialize',
        }),
      ).to.be.revertedWithCustomError(ServiceQualityOracleFactory, 'GovernorCannotBeZeroAddress')
    })
  })

  describe('Initialization', () => {
    it('should set the governor role correctly', async () => {
      const { serviceQualityOracle } = sharedContracts
      expect(await serviceQualityOracle.hasRole(GOVERNOR_ROLE, accounts.governor.address)).to.be.true
    })

    it('should not set oracle role to anyone initially', async () => {
      const { serviceQualityOracle } = sharedContracts
      expect(await serviceQualityOracle.hasRole(ORACLE_ROLE, accounts.operator.address)).to.be.false
    })

    it('should set default allowed period to 14 days', async () => {
      const { serviceQualityOracle } = sharedContracts
      expect(await serviceQualityOracle.getAllowedPeriod()).to.equal(14 * 24 * 60 * 60) // 14 days in seconds
    })

    it('should set quality checking to inactive by default', async () => {
      const { serviceQualityOracle } = sharedContracts
      expect(await serviceQualityOracle.isQualityCheckingActive()).to.be.false
    })

    it('should set default oracle update timeout to 7 days', async () => {
      const { serviceQualityOracle } = sharedContracts
      expect(await serviceQualityOracle.getOracleUpdateTimeout()).to.equal(7 * 24 * 60 * 60) // 7 days in seconds
    })

    it('should initialize lastOracleUpdateTime to 0', async () => {
      const { serviceQualityOracle } = sharedContracts
      expect(await serviceQualityOracle.getLastOracleUpdateTime()).to.equal(0)
    })

    it('should revert when initialize is called more than once', async () => {
      const { serviceQualityOracle } = sharedContracts

      // Try to call initialize again
      await expect(serviceQualityOracle.initialize(accounts.governor.address)).to.be.revertedWithCustomError(
        serviceQualityOracle,
        'InvalidInitialization',
      )
    })
  })

  describe('Oracle Management', () => {
    it('should allow operator to grant oracle role', async () => {
      const { serviceQualityOracle } = sharedContracts

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)

      // Operator grants oracle role
      await serviceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.user.address)
      expect(await serviceQualityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.true
    })

    it('should allow operator to revoke oracle role', async () => {
      const { serviceQualityOracle } = sharedContracts

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)

      // Grant oracle role first
      await serviceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.user.address)
      expect(await serviceQualityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.true

      // Revoke role
      await serviceQualityOracle.connect(accounts.operator).revokeRole(ORACLE_ROLE, accounts.user.address)
      expect(await serviceQualityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.false
    })

    // Access control tests moved to consolidated/AccessControl.test.ts
  })

  describe('Operator Functions', () => {
    beforeEach(async () => {
      const { serviceQualityOracle } = sharedContracts

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
    })

    it('should allow operator to set allowed period', async () => {
      const { serviceQualityOracle } = sharedContracts
      const newAllowedPeriod = 14 * 24 * 60 * 60 // 14 days

      // Set allowed period
      await serviceQualityOracle.connect(accounts.operator).setAllowedPeriod(newAllowedPeriod)

      // Check if allowed period was updated
      expect(await serviceQualityOracle.getAllowedPeriod()).to.equal(newAllowedPeriod)
    })

    it('should handle idempotent operations correctly', async () => {
      const { serviceQualityOracle } = sharedContracts

      // Test setting same allowed period
      const currentAllowedPeriod = await serviceQualityOracle.getAllowedPeriod()
      let result = await serviceQualityOracle
        .connect(accounts.operator)
        .setAllowedPeriod.staticCall(currentAllowedPeriod)
      expect(result).to.be.true

      // Verify no event emitted for same value
      let tx = await serviceQualityOracle.connect(accounts.operator).setAllowedPeriod(currentAllowedPeriod)
      let receipt = await tx.wait()
      expect(receipt.logs.length).to.equal(0)

      // Test setting new oracle update timeout
      const newTimeout = 60 * 24 * 60 * 60 // 60 days
      await serviceQualityOracle.connect(accounts.operator).setOracleUpdateTimeout(newTimeout)
      expect(await serviceQualityOracle.getOracleUpdateTimeout()).to.equal(newTimeout)

      // Test setting same oracle update timeout
      result = await serviceQualityOracle.connect(accounts.operator).setOracleUpdateTimeout.staticCall(newTimeout)
      expect(result).to.be.true

      // Verify no event emitted for same value
      tx = await serviceQualityOracle.connect(accounts.operator).setOracleUpdateTimeout(newTimeout)
      receipt = await tx.wait()
      expect(receipt.logs.length).to.equal(0)
    })

    it('should allow operator to disable quality checking', async () => {
      const { serviceQualityOracle } = sharedContracts
      // Disable quality checking
      await serviceQualityOracle.connect(accounts.operator).setQualityChecking(false)

      // Check if quality checking is disabled
      expect(await serviceQualityOracle.isQualityCheckingActive()).to.be.false
    })

    it('should allow operator to enable quality checking', async () => {
      const { serviceQualityOracle } = sharedContracts
      // Disable quality checking first
      await serviceQualityOracle.connect(accounts.operator).setQualityChecking(false)
      expect(await serviceQualityOracle.isQualityCheckingActive()).to.be.false

      // Enable quality checking
      await serviceQualityOracle.connect(accounts.operator).setQualityChecking(true)

      // Check if quality checking is enabled
      expect(await serviceQualityOracle.isQualityCheckingActive()).to.be.true
    })

    it('should handle setQualityChecking return values and events correctly', async () => {
      const { serviceQualityOracle } = sharedContracts

      // Test 1: Return true when enabling quality checking that is already enabled
      await serviceQualityOracle.connect(accounts.operator).setQualityChecking(true)
      expect(await serviceQualityOracle.isQualityCheckingActive()).to.be.true

      const enableResult = await serviceQualityOracle.connect(accounts.operator).setQualityChecking.staticCall(true)
      expect(enableResult).to.be.true

      // Test 2: No event emitted when setting to same state (enabled)
      const enableTx = await serviceQualityOracle.connect(accounts.operator).setQualityChecking(true)
      const enableReceipt = await enableTx.wait()
      expect(enableReceipt.logs.length).to.equal(0)

      // Test 3: Return true when disabling quality checking that is already disabled
      await serviceQualityOracle.connect(accounts.operator).setQualityChecking(false)
      expect(await serviceQualityOracle.isQualityCheckingActive()).to.be.false

      const disableResult = await serviceQualityOracle.connect(accounts.operator).setQualityChecking.staticCall(false)
      expect(disableResult).to.be.true

      // Test 4: No event emitted when setting to same state (disabled)
      const disableTx = await serviceQualityOracle.connect(accounts.operator).setQualityChecking(false)
      const disableReceipt = await disableTx.wait()
      expect(disableReceipt.logs.length).to.equal(0)

      // Test 5: Events are emitted when state actually changes
      await expect(serviceQualityOracle.connect(accounts.operator).setQualityChecking(true))
        .to.emit(serviceQualityOracle, 'QualityCheckingUpdated')
        .withArgs(true)

      await expect(serviceQualityOracle.connect(accounts.operator).setQualityChecking(false))
        .to.emit(serviceQualityOracle, 'QualityCheckingUpdated')
        .withArgs(false)
    })

    // Access control tests moved to consolidated/AccessControl.test.ts
    // Event and return value tests consolidated into 'should handle setQualityChecking return values and events correctly'
  })

  describe('Indexer Management', () => {
    beforeEach(async () => {
      const { serviceQualityOracle } = sharedContracts

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)

      // Grant oracle role
      await serviceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)
    })

    it('should allow oracle to allow a single indexer', async () => {
      const { serviceQualityOracle } = sharedContracts
      // Allow indexer using allowIndexers with a single-element array
      await serviceQualityOracle.connect(accounts.operator).allowIndexers([accounts.indexer1.address], '0x')

      // Check if indexer is allowed
      expect(await serviceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.true

      // Check if allowed timestamp was updated
      const allowedTime = await serviceQualityOracle.getLastAllowedTime(accounts.indexer1.address)
      expect(allowedTime).to.be.gt(0)
    })

    it('should allow oracle to allow multiple indexers', async () => {
      const { serviceQualityOracle } = sharedContracts
      // Allow multiple indexers
      const indexers = [accounts.indexer1.address, accounts.indexer2.address]
      await serviceQualityOracle.connect(accounts.operator).allowIndexers(indexers, '0x')

      // Check if indexers are allowed
      expect(await serviceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.true
      expect(await serviceQualityOracle.isAllowed(accounts.indexer2.address)).to.be.true

      // Check if allowed timestamps were updated
      const allowedTime1 = await serviceQualityOracle.getLastAllowedTime(accounts.indexer1.address)
      const allowedTime2 = await serviceQualityOracle.getLastAllowedTime(accounts.indexer2.address)
      expect(allowedTime1).to.be.gt(0)
      expect(allowedTime2).to.be.gt(0)
    })

    it('should not update timestamp for indexer already allowed in the same block', async () => {
      const { serviceQualityOracle } = sharedContracts
      // Allow indexer first time
      await serviceQualityOracle.connect(accounts.operator).allowIndexers([accounts.indexer1.address], '0x')

      // Get the timestamp
      const initialAllowedTime = await serviceQualityOracle.getLastAllowedTime(accounts.indexer1.address)

      // Call allowIndexers again with the same indexer
      const result = await serviceQualityOracle
        .connect(accounts.operator)
        .allowIndexers.staticCall([accounts.indexer1.address], '0x')

      // The function should return 0 since the indexer was already allowed in this block
      expect(result).to.equal(0)

      // Verify the timestamp hasn't changed
      const finalAllowedTime = await serviceQualityOracle.getLastAllowedTime(accounts.indexer1.address)
      expect(finalAllowedTime).to.equal(initialAllowedTime)

      // Mine a new block
      await ethers.provider.send('evm_mine', [])

      // Now try again in a new block - it should return 1
      const newBlockResult = await serviceQualityOracle
        .connect(accounts.operator)
        .allowIndexers.staticCall([accounts.indexer1.address], '0x')

      // The function should return 1 since we're in a new block
      expect(newBlockResult).to.equal(1)
    })

    it('should revert when non-oracle tries to allow a single indexer', async () => {
      const { serviceQualityOracle } = sharedContracts
      await expect(
        serviceQualityOracle.connect(accounts.nonGovernor).allowIndexers([accounts.indexer1.address], '0x'),
      ).to.be.revertedWithCustomError(serviceQualityOracle, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when non-oracle tries to allow multiple indexers', async () => {
      const { serviceQualityOracle } = sharedContracts
      const indexers = [accounts.indexer1.address, accounts.indexer2.address]
      await expect(
        serviceQualityOracle.connect(accounts.nonGovernor).allowIndexers(indexers, '0x'),
      ).to.be.revertedWithCustomError(serviceQualityOracle, 'AccessControlUnauthorizedAccount')
    })

    it('should return correct count for various allowIndexers scenarios', async () => {
      const { serviceQualityOracle } = sharedContracts

      // Test 1: Single indexer should return 1
      const singleResult = await serviceQualityOracle
        .connect(accounts.operator)
        .allowIndexers.staticCall([accounts.indexer1.address], '0x')
      expect(singleResult).to.equal(1)

      // Test 2: Multiple indexers should return correct count
      const multipleIndexers = [accounts.indexer1.address, accounts.indexer2.address]
      const multipleResult = await serviceQualityOracle
        .connect(accounts.operator)
        .allowIndexers.staticCall(multipleIndexers, '0x')
      expect(multipleResult).to.equal(2)

      // Test 3: Empty array should return 0
      const emptyResult = await serviceQualityOracle.connect(accounts.operator).allowIndexers.staticCall([], '0x')
      expect(emptyResult).to.equal(0)

      // Test 4: Array with zero addresses should only count non-zero addresses
      const withZeroAddresses = [accounts.indexer1.address, ethers.ZeroAddress, accounts.indexer2.address]
      const zeroResult = await serviceQualityOracle
        .connect(accounts.operator)
        .allowIndexers.staticCall(withZeroAddresses, '0x')
      expect(zeroResult).to.equal(2)

      // Test 5: Array with duplicates should only count unique indexers
      const withDuplicates = [accounts.indexer1.address, accounts.indexer1.address, accounts.indexer2.address]
      const duplicateResult = await serviceQualityOracle
        .connect(accounts.operator)
        .allowIndexers.staticCall(withDuplicates, '0x')
      expect(duplicateResult).to.equal(2)
    })
  })

  describe('View Functions', () => {
    // Use shared contracts instead of deploying fresh ones for each test

    it('should return 0 when getting last allowed time for non-allowed indexer', async () => {
      // Use a fresh deployment to avoid contamination from previous tests
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()
      const freshServiceQualityOracle = await deployServiceQualityOracle(graphTokenAddress, accounts.governor)

      // This should return 0 for a fresh contract
      const lastAllowedTime = await freshServiceQualityOracle.getLastAllowedTime(accounts.indexer1.address)
      expect(lastAllowedTime).to.equal(0)
    })

    it('should return correct timestamp for allowed indexer', async function () {
      const { serviceQualityOracle } = sharedContracts

      // Grant operator role first (governor can grant operator role)
      await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      // Then operator can grant oracle role (operator is admin of oracle role)
      await serviceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Allow indexer
      await serviceQualityOracle.connect(accounts.operator).allowIndexers([accounts.indexer1.address], '0x')

      // Get the last allowed time
      const lastAllowedTime = await serviceQualityOracle.getLastAllowedTime(accounts.indexer1.address)

      // Get the current block timestamp
      const block = await ethers.provider.getBlock('latest')
      const blockTimestamp = block ? block.timestamp : 0

      // The last allowed time should be close to the current block timestamp
      expect(lastAllowedTime).to.be.closeTo(blockTimestamp, 5) // Allow 5 seconds of difference
    })

    it('should correctly report if an indexer is allowed', async function () {
      // Use a fresh deployment to avoid shared state contamination
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()
      const freshServiceQualityOracle = await deployServiceQualityOracle(graphTokenAddress, accounts.governor)

      // Grant necessary roles (follow role hierarchy)
      await freshServiceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await freshServiceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable quality checking first (since it's disabled by default)
      await freshServiceQualityOracle.connect(accounts.operator).setQualityChecking(true)

      // First, set a non-zero lastOracleUpdateTime to prevent the timeout condition from triggering
      await freshServiceQualityOracle.connect(accounts.operator).allowIndexers([accounts.nonGovernor.address], '0x')

      // Now check if our test indexer is allowed (it shouldn't be)
      expect(await freshServiceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.false

      // Allow indexer
      await freshServiceQualityOracle.connect(accounts.operator).allowIndexers([accounts.indexer1.address], '0x')
      expect(await freshServiceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.true
    })

    it('should correctly report if an oracle is authorized', async function () {
      const { serviceQualityOracle } = sharedContracts

      // Grant operator role to perform role management
      await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)

      // Initially, user should not be an oracle
      expect(await serviceQualityOracle.isAuthorizedOracle(accounts.user.address)).to.be.false

      // Grant oracle role
      await serviceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.user.address)
      expect(await serviceQualityOracle.isAuthorizedOracle(accounts.user.address)).to.be.true

      // Revoke oracle role
      await serviceQualityOracle.connect(accounts.operator).revokeRole(ORACLE_ROLE, accounts.user.address)
      expect(await serviceQualityOracle.isAuthorizedOracle(accounts.user.address)).to.be.false
    })

    it('should return true for all indexers when quality checking is disabled', async function () {
      // Use a fresh deployment to avoid shared state contamination
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()
      const freshServiceQualityOracle = await deployServiceQualityOracle(graphTokenAddress, accounts.governor)

      // Grant necessary roles (follow role hierarchy)
      await freshServiceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await freshServiceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable quality checking first (since it's disabled by default)
      await freshServiceQualityOracle.connect(accounts.operator).setQualityChecking(true)

      // First, set a non-zero lastOracleUpdateTime to prevent the timeout condition from triggering
      await freshServiceQualityOracle.connect(accounts.operator).allowIndexers([accounts.nonGovernor.address], '0x')

      // Set a very long oracle update timeout to prevent that condition from triggering
      await freshServiceQualityOracle.connect(accounts.operator).setOracleUpdateTimeout(365 * 24 * 60 * 60) // 1 year

      // Now check if our test indexer is allowed (it shouldn't be)
      expect(await freshServiceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.false

      // Disable quality checking
      await freshServiceQualityOracle.connect(accounts.operator).setQualityChecking(false)

      // Now indexer should be allowed even without being explicitly allowed
      expect(await freshServiceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.true
    })

    it('should return true for all indexers when oracle update timeout is exceeded', async function () {
      // Use a fresh deployment to avoid shared state contamination
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()
      const freshServiceQualityOracle = await deployServiceQualityOracle(graphTokenAddress, accounts.governor)

      // Grant necessary roles (follow role hierarchy)
      await freshServiceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await freshServiceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable quality checking first (since it's disabled by default)
      await freshServiceQualityOracle.connect(accounts.operator).setQualityChecking(true)

      // First, set a non-zero lastOracleUpdateTime to prevent the initial timeout condition from triggering
      await freshServiceQualityOracle.connect(accounts.operator).allowIndexers([accounts.nonGovernor.address], '0x')

      // Set a very long oracle update timeout initially
      await freshServiceQualityOracle.connect(accounts.operator).setOracleUpdateTimeout(365 * 24 * 60 * 60) // 1 year

      // Now check if our test indexer is allowed (it shouldn't be)
      expect(await freshServiceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.false

      // Set a short oracle update timeout
      await freshServiceQualityOracle.connect(accounts.operator).setOracleUpdateTimeout(60) // 1 minute

      // Advance time beyond the timeout
      await time.increase(120) // 2 minutes

      // Now indexer should be allowed even without being explicitly allowed
      expect(await freshServiceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.true
    })

    it('should return false for indexer after allowed period expires', async function () {
      const { serviceQualityOracle } = sharedContracts

      // Grant necessary roles (follow role hierarchy)
      await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await serviceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable quality checking first (since it's disabled by default)
      await serviceQualityOracle.connect(accounts.operator).setQualityChecking(true)

      // Set a very long oracle update timeout to prevent that condition from triggering
      await serviceQualityOracle.connect(accounts.operator).setOracleUpdateTimeout(365 * 24 * 60 * 60) // 1 year

      // Allow indexer
      await serviceQualityOracle.connect(accounts.operator).allowIndexers([accounts.indexer1.address], '0x')
      expect(await serviceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.true

      // Set a short allowed period
      await serviceQualityOracle.connect(accounts.operator).setAllowedPeriod(60) // 1 minute

      // Advance time beyond allowed period
      await time.increase(120) // 2 minutes

      // Now indexer should not be allowed
      expect(await serviceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.false
    })

    it('should return true for indexer after re-allowing', async function () {
      const { serviceQualityOracle } = sharedContracts

      // Grant necessary roles
      await serviceQualityOracle.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await serviceQualityOracle.connect(accounts.operator).grantRole(ORACLE_ROLE, accounts.operator.address)

      // Enable quality checking first (since it's disabled by default)
      await serviceQualityOracle.connect(accounts.operator).setQualityChecking(true)

      // Set a very long oracle update timeout to prevent that condition from triggering
      await serviceQualityOracle.connect(accounts.operator).setOracleUpdateTimeout(365 * 24 * 60 * 60) // 1 year

      // Allow indexer
      await serviceQualityOracle.connect(accounts.operator).allowIndexers([accounts.indexer1.address], '0x')

      // Set a short allowed period
      await serviceQualityOracle.connect(accounts.operator).setAllowedPeriod(60) // 1 minute

      // Advance time beyond allowed period
      await time.increase(120) // 2 minutes

      // Indexer should not be allowed
      expect(await serviceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.false

      // Re-allow indexer
      await serviceQualityOracle.connect(accounts.operator).allowIndexers([accounts.indexer1.address], '0x')

      // Now indexer should be allowed again
      expect(await serviceQualityOracle.isAllowed(accounts.indexer1.address)).to.be.true
    })
  })
})

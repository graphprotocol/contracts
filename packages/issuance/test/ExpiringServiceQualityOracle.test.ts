import { expect } from 'chai'
import { ethers } from 'hardhat'
import { time } from '@nomicfoundation/hardhat-network-helpers'
import {
  getTestAccounts,
  deployTestGraphToken,
  deployProxy,
  TestAccounts
} from './helpers/fixtures'
import { ExpiringServiceQualityOracle } from '../build/types'

// Role constants
const GOVERNOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GOVERNOR_ROLE"))
const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"))
const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"))

describe('ExpiringServiceQualityOracle', () => {
  let accounts: TestAccounts
  let expiringServiceQualityOracle: ExpiringServiceQualityOracle

  // Default validity period: 7 days in seconds
  const DEFAULT_VALIDITY_PERIOD = 7 * 24 * 60 * 60

  async function setupExpiringServiceQualityOracle() {
    // Deploy test GraphToken
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    // Deploy ExpiringServiceQualityOracle
    const ExpiringServiceQualityOracleFactory = await ethers.getContractFactory('ExpiringServiceQualityOracle')
    const expiringServiceQualityOracleImpl = await ExpiringServiceQualityOracleFactory.deploy(graphTokenAddress)

    // Create initialization data for the base contract
    const initData = ExpiringServiceQualityOracleFactory.interface.encodeFunctionData(
      'initialize(address)',
      [accounts.governor.address]
    )

    // Deploy proxy
    const proxy = await deployProxy(
      await expiringServiceQualityOracleImpl.getAddress(),
      accounts.governor.address,
      initData
    )

    // Get contract at proxy address
    const expiringServiceQualityOracle = ExpiringServiceQualityOracleFactory.attach(
      await proxy.getAddress()
    ) as unknown as ExpiringServiceQualityOracle

    // Set the validity period after initialization
    // First grant operator role to governor so they can set the validity period
    await expiringServiceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.governor.address)
    await expiringServiceQualityOracle.connect(accounts.governor).setValidityPeriod(DEFAULT_VALIDITY_PERIOD)
    // Now revoke the operator role from governor to ensure tests start with clean state
    await expiringServiceQualityOracle.connect(accounts.governor).revokeOperatorRole(accounts.governor.address)

    return { expiringServiceQualityOracle }
  }

  beforeEach(async () => {
    accounts = await getTestAccounts()
    const setup = await setupExpiringServiceQualityOracle()
    expiringServiceQualityOracle = setup.expiringServiceQualityOracle
  })

  describe('Initialization', () => {
    it('should set the governor role correctly', async () => {
      expect(await expiringServiceQualityOracle.hasRole(GOVERNOR_ROLE, accounts.governor.address)).to.be.true
    })

    it('should set the validity period correctly', async () => {
      expect(await expiringServiceQualityOracle.getValidityPeriod()).to.equal(DEFAULT_VALIDITY_PERIOD)
    })

    it('should allow setting zero validity period', async () => {
      // Grant operator role to governor for this test
      await expiringServiceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Set validity period to zero
      await expiringServiceQualityOracle.connect(accounts.operator).setValidityPeriod(0)

      // Check that the validity period was set to zero
      expect(await expiringServiceQualityOracle.getValidityPeriod()).to.equal(0)
    })
  })

  describe('Oracle Management', () => {
    it('should allow operator to grant oracle role', async () => {
      // Grant operator role to the operator account
      await expiringServiceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Operator grants oracle role
      await expiringServiceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.user.address)
      expect(await expiringServiceQualityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.true
    })

    it('should allow operator to revoke oracle role', async () => {
      // Grant operator role to the operator account
      await expiringServiceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role first
      await expiringServiceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.user.address)
      expect(await expiringServiceQualityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.true

      // Revoke role
      await expiringServiceQualityOracle.connect(accounts.operator).revokeOracleRole(accounts.user.address)
      expect(await expiringServiceQualityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.false
    })

    it('should not allow non-operator to grant oracle role', async () => {
      await expect(expiringServiceQualityOracle.connect(accounts.nonGovernor).grantOracleRole(accounts.user.address))
        .to.be.revertedWithCustomError(expiringServiceQualityOracle, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when governor without operator role tries to grant oracle role', async () => {
      // Verify governor doesn't have operator role by default (after fixture setup)
      expect(await expiringServiceQualityOracle.hasRole(OPERATOR_ROLE, accounts.governor.address)).to.be.false

      // Now test that governor without operator role can't grant oracle role
      await expect(expiringServiceQualityOracle.connect(accounts.governor).grantOracleRole(accounts.user.address))
        .to.be.revertedWithCustomError(expiringServiceQualityOracle, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('Operator Management', () => {
    it('should allow governor to grant operator role', async () => {
      await expiringServiceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)
      expect(await expiringServiceQualityOracle.hasRole(OPERATOR_ROLE, accounts.operator.address)).to.be.true
    })

    it('should allow governor to revoke operator role', async () => {
      await expiringServiceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)
      await expiringServiceQualityOracle.connect(accounts.governor).revokeOperatorRole(accounts.operator.address)
      expect(await expiringServiceQualityOracle.hasRole(OPERATOR_ROLE, accounts.operator.address)).to.be.false
    })

    it('should not allow non-governor to grant operator role', async () => {
      await expect(expiringServiceQualityOracle.connect(accounts.nonGovernor).grantOperatorRole(accounts.operator.address))
        .to.be.revertedWithCustomError(expiringServiceQualityOracle, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('Validity Period Management', () => {
    beforeEach(async () => {
      // Grant operator role
      await expiringServiceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)
    })

    it('should allow operator to set validity period', async () => {
      const newPeriod = 14 * 24 * 60 * 60 // 14 days
      await expiringServiceQualityOracle.connect(accounts.operator).setValidityPeriod(newPeriod)
      expect(await expiringServiceQualityOracle.getValidityPeriod()).to.equal(newPeriod)
    })

    it('should emit ValidityPeriodUpdated event when setting validity period', async () => {
      const newPeriod = 14 * 24 * 60 * 60 // 14 days
      await expect(expiringServiceQualityOracle.connect(accounts.operator).setValidityPeriod(newPeriod))
        .to.emit(expiringServiceQualityOracle, 'ValidityPeriodUpdated')
        .withArgs(DEFAULT_VALIDITY_PERIOD, newPeriod)
    })

    it('should allow setting zero validity period', async () => {
      await expiringServiceQualityOracle.connect(accounts.operator).setValidityPeriod(0)
      expect(await expiringServiceQualityOracle.getValidityPeriod()).to.equal(0)
    })

    it('should not allow non-operator to set validity period', async () => {
      await expect(expiringServiceQualityOracle.connect(accounts.nonGovernor).setValidityPeriod(100))
        .to.be.revertedWithCustomError(expiringServiceQualityOracle, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('Indexer Management', () => {
    beforeEach(async () => {
      // Grant operator role to the operator account
      await expiringServiceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role
      await expiringServiceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.operator.address)
    })

    it('should allow oracle to allow indexer', async () => {
      await expiringServiceQualityOracle.connect(accounts.operator).allowIndexer(accounts.indexer1.address, '0x')
      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true
    })

    it('should update lastValidationTime when allowing indexer', async () => {
      const tx = await expiringServiceQualityOracle.connect(accounts.operator).allowIndexer(accounts.indexer1.address, '0x')
      const receipt = await tx.wait()
      const blockTimestamp = (await ethers.provider.getBlock(receipt!.blockNumber))!.timestamp

      expect(await expiringServiceQualityOracle.getLastValidationTime(accounts.indexer1.address)).to.equal(blockTimestamp)
    })

    it('should allow oracle to allow multiple indexers', async () => {
      const indexers = [accounts.indexer1.address, accounts.indexer2.address]
      await expiringServiceQualityOracle.connect(accounts.operator).allowIndexers(indexers, '0x')

      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true
      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer2.address)).to.be.true
    })

    it('should allow oracle to deny indexer', async () => {
      // First allow the indexer
      await expiringServiceQualityOracle.connect(accounts.operator).allowIndexer(accounts.indexer1.address, '0x')
      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true

      // Then deny the indexer
      await expiringServiceQualityOracle.connect(accounts.operator).denyIndexer(accounts.indexer1.address, '0x')
      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.false
    })

    it('should allow oracle to deny multiple indexers', async () => {
      // First allow the indexers
      const indexers = [accounts.indexer1.address, accounts.indexer2.address]
      await expiringServiceQualityOracle.connect(accounts.operator).allowIndexers(indexers, '0x')

      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true
      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer2.address)).to.be.true

      // Then deny the indexers
      await expiringServiceQualityOracle.connect(accounts.operator).denyIndexers(indexers, '0x')
      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.false
      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer2.address)).to.be.false
    })

    it('should not allow non-oracle to allow indexer', async () => {
      await expect(expiringServiceQualityOracle.connect(accounts.nonGovernor).allowIndexer(accounts.indexer1.address, '0x'))
        .to.be.revertedWithCustomError(expiringServiceQualityOracle, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('Expiration Mechanism', () => {
    beforeEach(async () => {
      // Grant operator role to the operator account
      await expiringServiceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role
      await expiringServiceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.operator.address)

      // Allow indexer
      await expiringServiceQualityOracle.connect(accounts.operator).allowIndexer(accounts.indexer1.address, '0x')
    })

    it('should return true for indexer within validity period', async () => {
      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true
    })

    it('should return false for indexer after validity period', async () => {
      // Advance time beyond validity period
      await time.increase(DEFAULT_VALIDITY_PERIOD + 1)

      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.false
    })

    it('should return true for indexer after revalidation', async () => {
      // Advance time beyond validity period
      await time.increase(DEFAULT_VALIDITY_PERIOD + 1)

      // Revalidate indexer
      await expiringServiceQualityOracle.connect(accounts.operator).allowIndexer(accounts.indexer1.address, '0x')

      expect(await expiringServiceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true
    })


  })
})

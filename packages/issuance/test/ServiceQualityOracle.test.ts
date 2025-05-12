import { expect } from 'chai'
import { ethers } from 'hardhat'
import {
  getTestAccounts,
  deployTestGraphToken,
  deployServiceQualityOracle,
  TestAccounts
} from './helpers/fixtures'

// Role constants
const GOVERNOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GOVERNOR_ROLE"))
const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"))

describe('ServiceQualityOracle', () => {
  // Common variables
  let accounts: TestAccounts

  // Test fixtures
  async function setupServiceQualityOracle() {
    // Deploy test GraphToken
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    // Deploy ServiceQualityOracle with proxy
    const serviceQualityOracle = await deployServiceQualityOracle(
      graphTokenAddress,
      accounts.governor
    )

    return { serviceQualityOracle, graphToken }
  }

  beforeEach(async () => {
    // Get test accounts
    accounts = await getTestAccounts()
  })

  describe('Initialization', () => {
    it('should set the governor role correctly', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()
      expect(await serviceQualityOracle.hasRole(GOVERNOR_ROLE, accounts.governor.address)).to.be.true
    })

    it('should not set oracle role to anyone initially', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()
      expect(await serviceQualityOracle.hasRole(ORACLE_ROLE, accounts.operator.address)).to.be.false
    })
  })

  describe('Oracle Management', () => {
    it('should allow operator to grant oracle role', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Operator grants oracle role
      await serviceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.user.address)
      expect(await serviceQualityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.true
    })

    it('should allow operator to revoke oracle role', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role first
      await serviceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.user.address)
      expect(await serviceQualityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.true

      // Revoke role
      await serviceQualityOracle.connect(accounts.operator).revokeOracleRole(accounts.user.address)
      expect(await serviceQualityOracle.hasRole(ORACLE_ROLE, accounts.user.address)).to.be.false
    })

    it('should revert when non-operator tries to grant oracle role', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      await expect(serviceQualityOracle.connect(accounts.nonGovernor).grantOracleRole(accounts.user.address))
        .to.be.revertedWithCustomError(serviceQualityOracle, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when non-operator tries to revoke oracle role', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role first
      await serviceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.user.address)

      // Try to revoke with non-operator
      await expect(serviceQualityOracle.connect(accounts.nonGovernor).revokeOracleRole(accounts.user.address))
        .to.be.revertedWithCustomError(serviceQualityOracle, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when governor without operator role tries to grant oracle role', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Governor doesn't have operator role by default
      await expect(serviceQualityOracle.connect(accounts.governor).grantOracleRole(accounts.user.address))
        .to.be.revertedWithCustomError(serviceQualityOracle, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('Indexer Management', () => {
    it('should allow oracle to allow indexer', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role
      await serviceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.operator.address)

      // Allow indexer
      await serviceQualityOracle.connect(accounts.operator).allowIndexer(accounts.indexer1.address, '0x')

      // Check if indexer meets requirements
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true
    })

    it('should allow oracle to deny indexer', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role
      await serviceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.operator.address)

      // Allow indexer first
      await serviceQualityOracle.connect(accounts.operator).allowIndexer(accounts.indexer1.address, '0x')
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true

      // Deny indexer
      await serviceQualityOracle.connect(accounts.operator).denyIndexer(accounts.indexer1.address, '0x')
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.false
    })

    it('should allow oracle to allow multiple indexers', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role
      await serviceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.operator.address)

      // Allow multiple indexers
      const indexers = [accounts.indexer1.address, accounts.indexer2.address]
      await serviceQualityOracle.connect(accounts.operator).allowIndexers(indexers, '0x')

      // Check if indexers meet requirements
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer2.address)).to.be.true
    })

    it('should allow oracle to deny multiple indexers', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role
      await serviceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.operator.address)

      // Allow multiple indexers first
      const indexers = [accounts.indexer1.address, accounts.indexer2.address]
      await serviceQualityOracle.connect(accounts.operator).allowIndexers(indexers, '0x')
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer2.address)).to.be.true

      // Deny multiple indexers
      await serviceQualityOracle.connect(accounts.operator).denyIndexers(indexers, '0x')
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.false
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer2.address)).to.be.false
    })

    it('should revert when non-oracle tries to allow indexer', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      await expect(serviceQualityOracle.connect(accounts.nonGovernor).allowIndexer(accounts.indexer1.address, '0x'))
        .to.be.revertedWithCustomError(serviceQualityOracle, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when non-oracle tries to deny indexer', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      await expect(serviceQualityOracle.connect(accounts.nonGovernor).denyIndexer(accounts.indexer1.address, '0x'))
        .to.be.revertedWithCustomError(serviceQualityOracle, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('View Functions', () => {
    it('should correctly report if an indexer meets requirements', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant oracle role
      await serviceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.operator.address)

      // Initially, indexer should not meet requirements
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.false

      // Allow indexer
      await serviceQualityOracle.connect(accounts.operator).allowIndexer(accounts.indexer1.address, '0x')
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.true

      // Deny indexer
      await serviceQualityOracle.connect(accounts.operator).denyIndexer(accounts.indexer1.address, '0x')
      expect(await serviceQualityOracle.meetsRequirements(accounts.indexer1.address)).to.be.false
    })

    it('should correctly report if an oracle is authorized', async () => {
      const { serviceQualityOracle } = await setupServiceQualityOracle()

      // Grant operator role to the operator account
      await serviceQualityOracle.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Initially, operator should not be an oracle
      expect(await serviceQualityOracle.isAuthorizedOracle(accounts.operator.address)).to.be.false

      // Grant oracle role
      await serviceQualityOracle.connect(accounts.operator).grantOracleRole(accounts.operator.address)
      expect(await serviceQualityOracle.isAuthorizedOracle(accounts.operator.address)).to.be.true

      // Revoke oracle role
      await serviceQualityOracle.connect(accounts.operator).revokeOracleRole(accounts.operator.address)
      expect(await serviceQualityOracle.isAuthorizedOracle(accounts.operator.address)).to.be.false
    })
  })
})

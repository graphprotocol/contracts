import { expect } from 'chai'
import { ethers } from 'hardhat'
import {
  getTestAccounts,
  deployTestGraphToken,
  deployDirectAllocation,
  TestAccounts
} from './helpers/fixtures'

// Role constants
const GOVERNOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GOVERNOR_ROLE"))
const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"))

describe('DirectAllocation', () => {
  // Common variables
  let accounts: TestAccounts

  // Test fixtures
  async function setupDirectAllocation() {
    // Deploy test GraphToken
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    // Deploy DirectAllocation with proxy
    const directAllocation = await deployDirectAllocation(
      graphTokenAddress,
      accounts.governor
    )

    return { directAllocation, graphToken }
  }

  beforeEach(async () => {
    // Get test accounts
    accounts = await getTestAccounts()
  })

  describe('Initialization', () => {
    it('should set the governor role correctly', async () => {
      const { directAllocation } = await setupDirectAllocation()
      expect(await directAllocation.hasRole(GOVERNOR_ROLE, accounts.governor.address)).to.be.true
    })

    it('should not set operator role to anyone initially', async () => {
      const { directAllocation } = await setupDirectAllocation()
      expect(await directAllocation.hasRole(OPERATOR_ROLE, accounts.operator.address)).to.be.false
    })
  })

  describe('Role Management', () => {
    it('should allow governor to grant operator role', async () => {
      const { directAllocation } = await setupDirectAllocation()

      await directAllocation.connect(accounts.governor).grantOperatorRole(accounts.operator.address)
      expect(await directAllocation.hasRole(OPERATOR_ROLE, accounts.operator.address)).to.be.true
    })

    it('should allow governor to revoke operator role', async () => {
      const { directAllocation } = await setupDirectAllocation()

      // Grant role first
      await directAllocation.connect(accounts.governor).grantOperatorRole(accounts.operator.address)
      expect(await directAllocation.hasRole(OPERATOR_ROLE, accounts.operator.address)).to.be.true

      // Revoke role
      await directAllocation.connect(accounts.governor).revokeOperatorRole(accounts.operator.address)
      expect(await directAllocation.hasRole(OPERATOR_ROLE, accounts.operator.address)).to.be.false
    })

    it('should revert when non-governor tries to grant operator role', async () => {
      const { directAllocation } = await setupDirectAllocation()

      await expect(directAllocation.connect(accounts.nonGovernor).grantOperatorRole(accounts.operator.address))
        .to.be.revertedWithCustomError(directAllocation, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when non-governor tries to revoke operator role', async () => {
      const { directAllocation } = await setupDirectAllocation()

      // Grant role first
      await directAllocation.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Try to revoke with non-governor
      await expect(directAllocation.connect(accounts.nonGovernor).revokeOperatorRole(accounts.operator.address))
        .to.be.revertedWithCustomError(directAllocation, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('Token Management', () => {
    it('should allow operator to send tokens', async () => {
      const { directAllocation, graphToken } = await setupDirectAllocation()

      // Mint some tokens to the DirectAllocation contract
      await graphToken.mint(await directAllocation.getAddress(), ethers.parseEther('1000'))

      // Grant the operator role to the operator
      await directAllocation.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      const amount = ethers.parseEther('100')

      await expect(directAllocation.connect(accounts.operator).sendTokens(accounts.user.address, amount))
        .to.emit(directAllocation, 'TokensSent')
        .withArgs(accounts.user.address, amount)

      expect(await graphToken.balanceOf(accounts.user.address)).to.equal(amount)
    })

    it('should revert when non-operator tries to send tokens', async () => {
      const { directAllocation, graphToken } = await setupDirectAllocation()

      // Mint some tokens to the DirectAllocation contract
      await graphToken.mint(await directAllocation.getAddress(), ethers.parseEther('1000'))

      await expect(directAllocation.connect(accounts.nonGovernor).sendTokens(accounts.user.address, ethers.parseEther('100')))
        .to.be.revertedWithCustomError(directAllocation, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when paused', async () => {
      const { directAllocation, graphToken } = await setupDirectAllocation()

      // Mint some tokens to the DirectAllocation contract
      await graphToken.mint(await directAllocation.getAddress(), ethers.parseEther('1000'))

      // Grant the operator role to the operator
      await directAllocation.connect(accounts.governor).grantOperatorRole(accounts.operator.address)

      // Grant pause role to governor
      await directAllocation.connect(accounts.governor).grantPauseRole(accounts.governor.address)

      // Pause the contract
      await directAllocation.connect(accounts.governor).pause()

      await expect(directAllocation.connect(accounts.operator).sendTokens(accounts.user.address, ethers.parseEther('100')))
        .to.be.revertedWithCustomError(directAllocation, 'EnforcedPause')
    })
  })

  describe('Interface Implementation', () => {
    it('should implement preIssuanceAllocationChange as a no-op', async () => {
      const { directAllocation } = await setupDirectAllocation()

      // This should not revert
      await directAllocation.preIssuanceAllocationChange()
    })

    it('should implement setIssuanceAllocator as a no-op', async () => {
      const { directAllocation } = await setupDirectAllocation()

      // This should not revert
      await directAllocation.connect(accounts.governor).setIssuanceAllocator(accounts.nonGovernor.address)
    })
  })
})

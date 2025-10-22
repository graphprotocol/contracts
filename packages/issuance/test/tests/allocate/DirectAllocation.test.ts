import { expect } from 'chai'
import hre from 'hardhat'

const { ethers } = hre

const { upgrades } = require('hardhat')

import { deployTestGraphToken, getTestAccounts, SHARED_CONSTANTS } from '../common/fixtures'
import { GraphTokenHelper } from '../common/graphTokenHelper'
import { deployDirectAllocation } from './fixtures'

describe('DirectAllocation - Optimized & Consolidated', () => {
  // Common variables
  let accounts
  let sharedContracts

  // Pre-calculated role constants to avoid repeated async contract calls
  const GOVERNOR_ROLE = SHARED_CONSTANTS.GOVERNOR_ROLE
  const OPERATOR_ROLE = SHARED_CONSTANTS.OPERATOR_ROLE
  const PAUSE_ROLE = SHARED_CONSTANTS.PAUSE_ROLE

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy shared contracts once for most tests - PERFORMANCE OPTIMIZATION
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()
    const directAllocation = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    const directAllocationAddress = await directAllocation.getAddress()

    // Create helper
    const graphTokenHelper = new GraphTokenHelper(graphToken as any, accounts.governor)

    sharedContracts = {
      graphToken,
      directAllocation,
      graphTokenHelper,
      addresses: {
        graphToken: graphTokenAddress,
        directAllocation: directAllocationAddress,
      },
    }
  })

  // Fast state reset function for shared contracts - PERFORMANCE OPTIMIZATION
  async function resetContractState() {
    if (!sharedContracts) return

    const { directAllocation } = sharedContracts

    // Reset pause state
    try {
      if (await directAllocation.paused()) {
        await directAllocation.connect(accounts.governor).unpause()
      }
    } catch {
      // Ignore if not paused
    }

    // Remove all roles except governor (keep governor role intact)
    try {
      // Remove operator role from all accounts
      for (const account of [accounts.operator, accounts.user, accounts.nonGovernor]) {
        if (await directAllocation.hasRole(OPERATOR_ROLE, account.address)) {
          await directAllocation.connect(accounts.governor).revokeRole(OPERATOR_ROLE, account.address)
        }
        if (await directAllocation.hasRole(PAUSE_ROLE, account.address)) {
          await directAllocation.connect(accounts.governor).revokeRole(PAUSE_ROLE, account.address)
        }
      }

      // Remove pause role from governor if present
      if (await directAllocation.hasRole(PAUSE_ROLE, accounts.governor.address)) {
        await directAllocation.connect(accounts.governor).revokeRole(PAUSE_ROLE, accounts.governor.address)
      }
    } catch {
      // Ignore role management errors during reset
    }
  }

  beforeEach(async () => {
    await resetContractState()
  })

  // Test fixtures for tests that need fresh contracts
  async function setupDirectAllocation() {
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()
    const directAllocation = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    return { directAllocation, graphToken }
  }

  describe('Constructor Validation', () => {
    it('should revert when constructed with zero GraphToken address', async () => {
      const DirectAllocationFactory = await ethers.getContractFactory('DirectAllocation')
      await expect(DirectAllocationFactory.deploy(ethers.ZeroAddress)).to.be.revertedWithCustomError(
        DirectAllocationFactory,
        'GraphTokenCannotBeZeroAddress',
      )
    })
  })

  describe('Initialization', () => {
    it('should set the governor role correctly', async () => {
      const { directAllocation } = sharedContracts
      expect(await directAllocation.hasRole(GOVERNOR_ROLE, accounts.governor.address)).to.be.true
    })

    it('should not set operator role to anyone initially', async () => {
      const { directAllocation } = sharedContracts
      expect(await directAllocation.hasRole(OPERATOR_ROLE, accounts.operator.address)).to.be.false
    })

    it('should revert when initialize is called more than once', async () => {
      const { directAllocation } = sharedContracts
      await expect(directAllocation.initialize(accounts.governor.address)).to.be.revertedWithCustomError(
        directAllocation,
        'InvalidInitialization',
      )
    })

    it('should revert when initialized with zero governor address', async () => {
      const graphToken = await deployTestGraphToken()
      const graphTokenAddress = await graphToken.getAddress()

      // Try to deploy proxy with zero governor address - this should hit the BaseUpgradeable check
      const DirectAllocationFactory = await ethers.getContractFactory('DirectAllocation')
      await expect(
        upgrades.deployProxy(DirectAllocationFactory, [ethers.ZeroAddress], {
          constructorArgs: [graphTokenAddress],
          initializer: 'initialize',
        }),
      ).to.be.revertedWithCustomError(DirectAllocationFactory, 'GovernorCannotBeZeroAddress')
    })
  })

  describe('Role Management', () => {
    it('should manage operator role correctly and enforce access control', async () => {
      const { directAllocation } = sharedContracts

      // Test granting operator role
      await expect(directAllocation.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address))
        .to.emit(directAllocation, 'RoleGranted')
        .withArgs(OPERATOR_ROLE, accounts.operator.address, accounts.governor.address)

      expect(await directAllocation.hasRole(OPERATOR_ROLE, accounts.operator.address)).to.be.true

      // Test revoking operator role
      await expect(directAllocation.connect(accounts.governor).revokeRole(OPERATOR_ROLE, accounts.operator.address))
        .to.emit(directAllocation, 'RoleRevoked')
        .withArgs(OPERATOR_ROLE, accounts.operator.address, accounts.governor.address)

      expect(await directAllocation.hasRole(OPERATOR_ROLE, accounts.operator.address)).to.be.false
    })
  })

  describe('Token Management', () => {
    it('should handle token operations with proper access control and validation', async () => {
      // Use shared contracts for better performance
      const { directAllocation, graphToken, graphTokenHelper } = sharedContracts
      await resetContractState()

      // Setup: mint tokens and grant operator role
      await graphTokenHelper.mint(await directAllocation.getAddress(), ethers.parseEther('1000'))
      await directAllocation.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)

      // Test successful token sending with event emission
      const amount = ethers.parseEther('100')
      await expect(directAllocation.connect(accounts.operator).sendTokens(accounts.user.address, amount))
        .to.emit(directAllocation, 'TokensSent')
        .withArgs(accounts.user.address, amount)
      expect(await graphToken.balanceOf(accounts.user.address)).to.equal(amount)

      // Test zero amount sending
      await expect(directAllocation.connect(accounts.operator).sendTokens(accounts.user.address, 0))
        .to.emit(directAllocation, 'TokensSent')
        .withArgs(accounts.user.address, 0)

      // Test access control - operator should succeed, non-operator should fail
      await expect(
        directAllocation.connect(accounts.nonGovernor).sendTokens(accounts.user.address, ethers.parseEther('100')),
      ).to.be.revertedWithCustomError(directAllocation, 'AccessControlUnauthorizedAccount')

      // Test zero address validation - transfer to zero address will fail
      await expect(
        directAllocation.connect(accounts.operator).sendTokens(ethers.ZeroAddress, ethers.parseEther('100')),
      ).to.be.revertedWith('ERC20: transfer to the zero address')
    })

    it('should handle insufficient balance and pause states correctly', async () => {
      // Use fresh setup for this test
      const { directAllocation, graphToken } = await setupDirectAllocation()
      const graphTokenHelper = new GraphTokenHelper(graphToken as any, accounts.governor)

      // Test insufficient balance (no tokens minted)
      await directAllocation.connect(accounts.governor).grantRole(OPERATOR_ROLE, accounts.operator.address)
      await expect(
        directAllocation.connect(accounts.operator).sendTokens(accounts.user.address, ethers.parseEther('100')),
      ).to.be.revertedWith('ERC20: transfer amount exceeds balance')

      // Setup for pause test
      await graphTokenHelper.mint(await directAllocation.getAddress(), ethers.parseEther('1000'))
      await directAllocation.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await directAllocation.connect(accounts.governor).pause()

      // Test paused state
      await expect(
        directAllocation.connect(accounts.operator).sendTokens(accounts.user.address, ethers.parseEther('100')),
      ).to.be.revertedWithCustomError(directAllocation, 'EnforcedPause')
    })
  })

  describe('Pausability and Access Control', () => {
    beforeEach(async () => {
      await resetContractState()
    })

    it('should handle pause/unpause operations and access control', async () => {
      const { directAllocation } = sharedContracts

      // Grant pause role to governor and operator
      await directAllocation.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await directAllocation.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.operator.address)

      // Test basic pause/unpause with governor
      await directAllocation.connect(accounts.governor).pause()
      expect(await directAllocation.paused()).to.be.true
      await directAllocation.connect(accounts.governor).unpause()
      expect(await directAllocation.paused()).to.be.false

      // Test multiple pause/unpause cycles with operator
      await directAllocation.connect(accounts.operator).pause()
      expect(await directAllocation.paused()).to.be.true
      await directAllocation.connect(accounts.operator).unpause()
      expect(await directAllocation.paused()).to.be.false
      await directAllocation.connect(accounts.operator).pause()
      expect(await directAllocation.paused()).to.be.true
      await directAllocation.connect(accounts.operator).unpause()
      expect(await directAllocation.paused()).to.be.false

      // Test access control for unauthorized accounts
      await expect(directAllocation.connect(accounts.nonGovernor).pause()).to.be.revertedWithCustomError(
        directAllocation,
        'AccessControlUnauthorizedAccount',
      )

      // Setup for unpause access control test
      await directAllocation.connect(accounts.governor).pause()
      await expect(directAllocation.connect(accounts.nonGovernor).unpause()).to.be.revertedWithCustomError(
        directAllocation,
        'AccessControlUnauthorizedAccount',
      )
    })

    it('should support all BaseUpgradeable constants', async () => {
      const { directAllocation } = sharedContracts

      // Test that constants are accessible
      expect(await directAllocation.MILLION()).to.equal(1_000_000)
      expect(await directAllocation.GOVERNOR_ROLE()).to.equal(GOVERNOR_ROLE)
      expect(await directAllocation.PAUSE_ROLE()).to.equal(PAUSE_ROLE)
      expect(await directAllocation.OPERATOR_ROLE()).to.equal(OPERATOR_ROLE)
    })

    it('should maintain role hierarchy properly', async () => {
      const { directAllocation } = sharedContracts

      // Governor should be admin of all roles
      expect(await directAllocation.getRoleAdmin(GOVERNOR_ROLE)).to.equal(GOVERNOR_ROLE)
      expect(await directAllocation.getRoleAdmin(PAUSE_ROLE)).to.equal(GOVERNOR_ROLE)
      expect(await directAllocation.getRoleAdmin(OPERATOR_ROLE)).to.equal(GOVERNOR_ROLE)
    })
  })

  describe('Interface Implementation', () => {
    it('should implement beforeIssuanceAllocationChange as a no-op and emit event', async () => {
      const { directAllocation } = sharedContracts
      // This should not revert and should emit an event
      await expect(directAllocation.beforeIssuanceAllocationChange()).to.emit(
        directAllocation,
        'BeforeIssuanceAllocationChange',
      )
    })

    it('should implement setIssuanceAllocator as a no-op', async () => {
      const { directAllocation } = sharedContracts
      // This should not revert
      await directAllocation.connect(accounts.governor).setIssuanceAllocator(accounts.nonGovernor.address)
    })
  })
})

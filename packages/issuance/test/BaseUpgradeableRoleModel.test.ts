import { expect } from 'chai'
import { ethers } from 'hardhat'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { BaseUpgradeable } from '../build/types'
import { deployBaseUpgradeable, deployTestGraphToken } from './helpers/fixtures'

describe('BaseUpgradeable Role Model', () => {
  let baseUpgradeable: BaseUpgradeable
  let graphToken: SignerWithAddress
  let governor: SignerWithAddress
  let nonGovernor: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress

  const GOVERNOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes('GOVERNOR_ROLE'))
  const PAUSE_ROLE = ethers.keccak256(ethers.toUtf8Bytes('PAUSE_ROLE'))
  const DEFAULT_ADMIN_ROLE = ethers.ZeroHash

  beforeEach(async () => {
    // Get signers
    [governor, nonGovernor, user1, user2, graphToken] = await ethers.getSigners()

    // Deploy test GraphToken
    const testGraphToken = await deployTestGraphToken()
    const graphTokenAddress = await testGraphToken.getAddress()

    // Deploy BaseUpgradeable through a proxy
    baseUpgradeable = await deployBaseUpgradeable(graphTokenAddress, governor)
  })

  describe('Role Initialization', () => {
    it('should set GOVERNOR_ROLE to the governor address', async () => {
      expect(await baseUpgradeable.hasRole(GOVERNOR_ROLE, governor.address)).to.be.true
    })

    it('should not set DEFAULT_ADMIN_ROLE to the governor address', async () => {
      expect(await baseUpgradeable.hasRole(DEFAULT_ADMIN_ROLE, governor.address)).to.be.false
    })

    it('should not set PAUSE_ROLE to anyone initially', async () => {
      expect(await baseUpgradeable.hasRole(PAUSE_ROLE, governor.address)).to.be.false
      expect(await baseUpgradeable.hasRole(PAUSE_ROLE, nonGovernor.address)).to.be.false
    })
  })

  describe('Role Management', () => {
    it('should allow governor to grant pause role', async () => {
      await baseUpgradeable.connect(governor).grantPauseRole(user1.address)
      expect(await baseUpgradeable.hasRole(PAUSE_ROLE, user1.address)).to.be.true
    })

    it('should allow governor to revoke pause role', async () => {
      await baseUpgradeable.connect(governor).grantPauseRole(user1.address)
      await baseUpgradeable.connect(governor).revokePauseRole(user1.address)
      expect(await baseUpgradeable.hasRole(PAUSE_ROLE, user1.address)).to.be.false
    })

    it('should allow governor to grant governor role', async () => {
      await baseUpgradeable.connect(governor).grantGovernorRole(user1.address)
      expect(await baseUpgradeable.hasRole(GOVERNOR_ROLE, user1.address)).to.be.true
    })

    it('should allow governor to revoke governor role', async () => {
      await baseUpgradeable.connect(governor).grantGovernorRole(user1.address)
      await baseUpgradeable.connect(governor).revokeGovernorRole(user1.address)
      expect(await baseUpgradeable.hasRole(GOVERNOR_ROLE, user1.address)).to.be.false
    })

    it('should not allow non-governor to grant pause role', async () => {
      await expect(baseUpgradeable.connect(nonGovernor).grantPauseRole(user1.address))
        .to.be.revertedWithCustomError(baseUpgradeable, 'AccessControlUnauthorizedAccount')
    })

    it('should not allow non-governor to revoke pause role', async () => {
      await baseUpgradeable.connect(governor).grantPauseRole(user1.address)
      await expect(baseUpgradeable.connect(nonGovernor).revokePauseRole(user1.address))
        .to.be.revertedWithCustomError(baseUpgradeable, 'AccessControlUnauthorizedAccount')
    })

    it('should not allow non-governor to grant governor role', async () => {
      await expect(baseUpgradeable.connect(nonGovernor).grantGovernorRole(user1.address))
        .to.be.revertedWithCustomError(baseUpgradeable, 'AccessControlUnauthorizedAccount')
    })

    it('should not allow non-governor to revoke governor role', async () => {
      await expect(baseUpgradeable.connect(nonGovernor).revokeGovernorRole(governor.address))
        .to.be.revertedWithCustomError(baseUpgradeable, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('Pause Functionality', () => {
    it('should allow governor to pause', async () => {
      await baseUpgradeable.connect(governor).grantPauseRole(governor.address)
      await baseUpgradeable.connect(governor).pause()
      expect(await baseUpgradeable.paused()).to.be.true
    })

    it('should allow pause role holder to pause', async () => {
      await baseUpgradeable.connect(governor).grantPauseRole(user1.address)
      await baseUpgradeable.connect(user1).pause()
      expect(await baseUpgradeable.paused()).to.be.true
    })

    it('should not allow non-pause role holder to pause', async () => {
      await expect(baseUpgradeable.connect(nonGovernor).pause())
        .to.be.revertedWithCustomError(baseUpgradeable, 'AccessControlUnauthorizedAccount')
    })

    it('should allow governor to unpause', async () => {
      await baseUpgradeable.connect(governor).grantPauseRole(governor.address)
      await baseUpgradeable.connect(governor).pause()
      await baseUpgradeable.connect(governor).unpause()
      expect(await baseUpgradeable.paused()).to.be.false
    })

    it('should allow pause role holder to unpause', async () => {
      await baseUpgradeable.connect(governor).grantPauseRole(user1.address)
      await baseUpgradeable.connect(user1).pause()
      await baseUpgradeable.connect(user1).unpause()
      expect(await baseUpgradeable.paused()).to.be.false
    })

    it('should not allow non-pause role holder to unpause', async () => {
      await baseUpgradeable.connect(governor).grantPauseRole(governor.address)
      await baseUpgradeable.connect(governor).pause()
      await expect(baseUpgradeable.connect(nonGovernor).unpause())
        .to.be.revertedWithCustomError(baseUpgradeable, 'AccessControlUnauthorizedAccount')
    })
  })
})

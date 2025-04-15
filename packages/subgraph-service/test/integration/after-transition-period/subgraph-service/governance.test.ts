import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HDNodeWallet } from 'ethers'
import hre from 'hardhat'

import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { SubgraphService } from '../../../../typechain-types'

describe('Subgraph Service Governance', () => {
  let subgraphService: SubgraphService
  let snapshotId: string

  // Test addresses
  let governor: SignerWithAddress
  let nonOwner: HDNodeWallet
  let pauseGuardian: HDNodeWallet

  before(async () => {
    const graph = hre.graph()
    subgraphService = graph.subgraphService.contracts.SubgraphService as unknown as SubgraphService

    // Get signers
    const signers = await ethers.getSigners()
    governor = signers[1]
    nonOwner = ethers.Wallet.createRandom()
    nonOwner = nonOwner.connect(ethers.provider)
    pauseGuardian = ethers.Wallet.createRandom()
    pauseGuardian = pauseGuardian.connect(ethers.provider)

    // Set eth balance for non-owner and pause guardian
    await ethers.provider.send('hardhat_setBalance', [nonOwner.address, '0x56BC75E2D63100000'])
    await ethers.provider.send('hardhat_setBalance', [pauseGuardian.address, '0x56BC75E2D63100000'])
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Minimum Provision Tokens', () => {
    it('should set minimum provision tokens', async () => {
      const newMinimumProvisionTokens = ethers.parseEther('1000')
      await subgraphService.connect(governor).setMinimumProvisionTokens(newMinimumProvisionTokens)

      // Get the provision tokens range
      const [minTokens, maxTokens] = await subgraphService.getProvisionTokensRange()
      expect(minTokens).to.equal(newMinimumProvisionTokens, 'Minimum provision tokens should be set')
      expect(maxTokens).to.equal(ethers.MaxUint256, 'Maximum provision tokens should be set')
    })

    it('should not allow non-owner to set minimum provision tokens', async () => {
      const newMinimumProvisionTokens = ethers.parseEther('1000')
      await expect(
        subgraphService.connect(nonOwner).setMinimumProvisionTokens(newMinimumProvisionTokens),
        'Non-owner should not be able to set minimum provision tokens',
      ).to.be.revertedWithCustomError(subgraphService, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Pause Guardian', () => {
    it('should set pause guardian and allow them to pause the service', async () => {
      // Set pause guardian
      await subgraphService.connect(governor).setPauseGuardian(pauseGuardian.address, true)

      // Pause guardian should be able to pause the service
      await subgraphService.connect(pauseGuardian).pause()
      expect(await subgraphService.paused(), 'Pause guardian should be able to pause the service').to.be.true
    })

    it('should remove pause guardian and prevent them from pausing the service', async () => {
      // First set pause guardian
      await subgraphService.connect(governor).setPauseGuardian(pauseGuardian.address, true)

      // Check that pause guardian can pause the service
      await subgraphService.connect(pauseGuardian).pause()
      expect(await subgraphService.paused(), 'Pause guardian should be able to pause the service').to.be.true

      // Then remove pause guardian
      await subgraphService.connect(governor).setPauseGuardian(pauseGuardian.address, false)

      // Pause guardian should no longer be able to unpause the service
      await expect(
        subgraphService.connect(pauseGuardian).unpause(),
        'Pause guardian should no longer be able to unpause the service',
      ).to.be.revertedWithCustomError(subgraphService, 'DataServicePausableNotPauseGuardian')
    })

    it('should not allow non-owner to set pause guardian', async () => {
      await expect(
        subgraphService.connect(nonOwner).setPauseGuardian(pauseGuardian.address, true),
        'Non-owner should not be able to set pause guardian',
      ).to.be.revertedWithCustomError(subgraphService, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Delegation Ratio', () => {
    it('should set delegation ratio', async () => {
      const newDelegationRatio = 5
      await subgraphService.connect(governor).setDelegationRatio(newDelegationRatio)
      expect(await subgraphService.getDelegationRatio(), 'Delegation ratio should be set').to.equal(newDelegationRatio)
    })

    it('should not allow non-owner to set delegation ratio', async () => {
      const newDelegationRatio = 5
      await expect(
        subgraphService.connect(nonOwner).setDelegationRatio(newDelegationRatio),
        'Non-owner should not be able to set delegation ratio',
      ).to.be.revertedWithCustomError(subgraphService, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Stake to Fees Ratio', () => {
    it('should set stake to fees ratio', async () => {
      const newStakeToFeesRatio = ethers.parseEther('1')
      await subgraphService.connect(governor).setStakeToFeesRatio(newStakeToFeesRatio)

      // Get the stake to fees ratio by calling a function that uses it
      const stakeToFeesRatio = await subgraphService.stakeToFeesRatio()
      expect(stakeToFeesRatio).to.equal(newStakeToFeesRatio, 'Stake to fees ratio should be set')
    })

    it('should not allow non-owner to set stake to fees ratio', async () => {
      const newStakeToFeesRatio = ethers.parseEther('1')
      await expect(
        subgraphService.connect(nonOwner).setStakeToFeesRatio(newStakeToFeesRatio),
        'Non-owner should not be able to set stake to fees ratio',
      ).to.be.revertedWithCustomError(subgraphService, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Max POI Staleness', () => {
    it('should set max POI staleness', async () => {
      const newMaxPOIStaleness = 3600 // 1 hour in seconds
      await subgraphService.connect(governor).setMaxPOIStaleness(newMaxPOIStaleness)

      // Get the max POI staleness
      const maxPOIStaleness = await subgraphService.maxPOIStaleness()
      expect(maxPOIStaleness).to.equal(newMaxPOIStaleness, 'Max POI staleness should be set')
    })

    it('should not allow non-owner to set max POI staleness', async () => {
      const newMaxPOIStaleness = 3600
      await expect(
        subgraphService.connect(nonOwner).setMaxPOIStaleness(newMaxPOIStaleness),
        'Non-owner should not be able to set max POI staleness',
      ).to.be.revertedWithCustomError(subgraphService, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Curation Cut', () => {
    it('should set curation cut', async () => {
      const newCurationCut = 100000 // 10% in PPM
      await subgraphService.connect(governor).setCurationCut(newCurationCut)

      // Get the curation cut
      const curationCut = await subgraphService.curationFeesCut()
      expect(curationCut).to.equal(newCurationCut, 'Curation cut should be set')
    })

    it('should not allow non-owner to set curation cut', async () => {
      const newCurationCut = 100000
      await expect(
        subgraphService.connect(nonOwner).setCurationCut(newCurationCut),
        'Non-owner should not be able to set curation cut',
      ).to.be.revertedWithCustomError(subgraphService, 'OwnableUnauthorizedAccount')
    })
  })
})

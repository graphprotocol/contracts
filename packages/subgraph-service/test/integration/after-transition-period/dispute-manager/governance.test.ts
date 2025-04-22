import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { DisputeManager } from '../../../../typechain-types'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('DisputeManager Governance', () => {
  let disputeManager: DisputeManager
  let snapshotId: string

  // Test addresses
  let governor: HardhatEthersSigner
  let nonOwner: HardhatEthersSigner
  let newArbitrator: HardhatEthersSigner
  let newSubgraphService: HardhatEthersSigner

  before(async () => {
    const graph = hre.graph()
    disputeManager = graph.subgraphService.contracts.DisputeManager

    // Get signers
    governor = await graph.accounts.getGovernor()
    ;[nonOwner, newArbitrator, newSubgraphService] = await graph.accounts.getTestAccounts()
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Arbitrator', () => {
    it('should set arbitrator', async () => {
      await disputeManager.connect(governor).setArbitrator(newArbitrator.address)
      expect(await disputeManager.arbitrator()).to.equal(newArbitrator.address)
    })

    it('should not allow non-owner to set arbitrator', async () => {
      await expect(
        disputeManager.connect(nonOwner).setArbitrator(newArbitrator.address),
      ).to.be.revertedWithCustomError(disputeManager, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Dispute Period', () => {
    it('should set dispute period', async () => {
      const newDisputePeriod = 7 * 24 * 60 * 60 // 7 days in seconds
      await disputeManager.connect(governor).setDisputePeriod(newDisputePeriod)
      expect(await disputeManager.disputePeriod()).to.equal(newDisputePeriod)
    })

    it('should not allow non-owner to set dispute period', async () => {
      const newDisputePeriod = 7 * 24 * 60 * 60
      await expect(
        disputeManager.connect(nonOwner).setDisputePeriod(newDisputePeriod),
      ).to.be.revertedWithCustomError(disputeManager, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Dispute Deposit', () => {
    it('should set dispute deposit', async () => {
      const newDisputeDeposit = ethers.parseEther('1000')
      await disputeManager.connect(governor).setDisputeDeposit(newDisputeDeposit)
      expect(await disputeManager.disputeDeposit()).to.equal(newDisputeDeposit)
    })

    it('should not allow non-owner to set dispute deposit', async () => {
      const newDisputeDeposit = ethers.parseEther('1000')
      await expect(
        disputeManager.connect(nonOwner).setDisputeDeposit(newDisputeDeposit),
      ).to.be.revertedWithCustomError(disputeManager, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Fisherman Rewards Cut', () => {
    it('should set fisherman rewards cut', async () => {
      const newFishermanRewardsCut = 100000 // 10% in PPM
      await disputeManager.connect(governor).setFishermanRewardCut(newFishermanRewardsCut)
      expect(await disputeManager.fishermanRewardCut()).to.equal(newFishermanRewardsCut)
    })

    it('should not allow non-owner to set fisherman rewards cut', async () => {
      const newFishermanRewardsCut = 100000
      await expect(
        disputeManager.connect(nonOwner).setFishermanRewardCut(newFishermanRewardsCut),
      ).to.be.revertedWithCustomError(disputeManager, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Max Slashing Cut', () => {
    it('should set max slashing cut', async () => {
      const newMaxSlashingCut = 200000 // 20% in PPM
      await disputeManager.connect(governor).setMaxSlashingCut(newMaxSlashingCut)
      expect(await disputeManager.maxSlashingCut()).to.equal(newMaxSlashingCut)
    })

    it('should not allow non-owner to set max slashing cut', async () => {
      const newMaxSlashingCut = 200000
      await expect(
        disputeManager.connect(nonOwner).setMaxSlashingCut(newMaxSlashingCut),
      ).to.be.revertedWithCustomError(disputeManager, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Subgraph Service Address', () => {
    it('should set subgraph service address', async () => {
      await disputeManager.connect(governor).setSubgraphService(newSubgraphService.address)
      expect(await disputeManager.subgraphService()).to.equal(newSubgraphService.address)
    })

    it('should not allow non-owner to set subgraph service address', async () => {
      await expect(
        disputeManager.connect(nonOwner).setSubgraphService(newSubgraphService.address),
      ).to.be.revertedWithCustomError(disputeManager, 'OwnableUnauthorizedAccount')
    })
  })
})

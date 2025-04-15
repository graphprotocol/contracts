import { ethers } from 'hardhat'
import { EventLog } from 'ethers'
import { expect } from 'chai'
import hre from 'hardhat'

import { DisputeManager, IGraphToken, IHorizonStaking, SubgraphService } from '../../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { indexers } from '../../../../tasks/test/fixtures/indexers'

describe('Indexing Disputes', () => {
  let disputeManager: DisputeManager
  let graphToken: IGraphToken
  let staking: IHorizonStaking
  let subgraphService: SubgraphService

  let snapshotId: string

  // Test addresses
  let fisherman: SignerWithAddress
  let arbitrator: SignerWithAddress
  let indexer: SignerWithAddress

  let allocationId: string

  // Dispute manager variables
  let disputeDeposit: bigint
  let fishermanRewardCut: bigint
  let disputePeriod: bigint

  before(async () => {
    // Get contracts
    const graph = hre.graph()
    disputeManager = graph.subgraphService.contracts.DisputeManager as unknown as DisputeManager
    graphToken = graph.horizon.contracts.GraphToken as unknown as IGraphToken
    staking = graph.horizon.contracts.HorizonStaking as unknown as IHorizonStaking
    subgraphService = graph.subgraphService.contracts.SubgraphService as unknown as SubgraphService

    // Get signers
    const signers = await ethers.getSigners()
    fisherman = signers[0]
    arbitrator = signers[2]

    // Get indexer
    const indexerFixture = indexers[0]
    indexer = await ethers.getSigner(indexerFixture.address)

    // Get allocation
    const allocation = indexerFixture.allocations[0]
    allocationId = allocation.allocationID

    // Dispute manager variables
    disputeDeposit = await disputeManager.disputeDeposit()
    fishermanRewardCut = await disputeManager.fishermanRewardCut()
    disputePeriod = await disputeManager.disputePeriod()
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Fisherman', () => {
    it('should allow fisherman to create an indexing dispute', async () => {
      // Create dispute
      const poi = ethers.keccak256(ethers.toUtf8Bytes('test-poi'))

      // Approve dispute manager for dispute deposit
      await graphToken.connect(fisherman).approve(disputeManager.target, disputeDeposit)

      // Create dispute
      const tx = await disputeManager.connect(fisherman).createIndexingDispute(allocationId, poi)
      const receipt = await tx.wait()

      // Get dispute ID from event
      const disputeCreatedEvent = receipt?.logs.find(
        log => log instanceof EventLog && log.fragment?.name === 'IndexingDisputeCreated',
      ) as EventLog
      const disputeId = disputeCreatedEvent?.args[0]

      // Verify dispute was created
      const dispute = await disputeManager.disputes(disputeId)
      expect(dispute.indexer).to.equal(indexer.address, 'Indexer address mismatch')
      expect(dispute.fisherman).to.equal(fisherman.address, 'Fisherman address mismatch')
      expect(dispute.disputeType).to.equal(1, 'Dispute type should be indexing')
      expect(dispute.status).to.equal(4, 'Dispute status should be pending')
    })

    it('should allow fisherman to cancel an indexing dispute', async () => {
      // Create dispute
      const poi = ethers.keccak256(ethers.toUtf8Bytes('test-poi'))

      // Approve dispute manager for dispute deposit
      await graphToken.connect(fisherman).approve(disputeManager.target, disputeDeposit)

      // Create dispute
      const tx = await disputeManager.connect(fisherman).createIndexingDispute(allocationId, poi)
      const receipt = await tx.wait()

      // Get dispute ID from event
      const disputeCreatedEvent = receipt?.logs.find(
        log => log instanceof EventLog && log.fragment?.name === 'IndexingDisputeCreated',
      ) as EventLog
      const disputeId = disputeCreatedEvent?.args[0]

      // Get fisherman's balance before canceling dispute
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Pass dispute period
      await ethers.provider.send('evm_increaseTime', [Number(disputePeriod) + 1])
      await ethers.provider.send('evm_mine', [])

      // Cancel dispute
      await disputeManager.connect(fisherman).cancelDispute(disputeId)

      // Verify dispute was canceled
      const updatedDispute = await disputeManager.disputes(disputeId)
      expect(updatedDispute.status).to.equal(5, 'Dispute status should be canceled')

      // Verify fisherman got the deposit back
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      expect(fishermanBalance).to.equal(fishermanBalanceBefore + disputeDeposit, 'Fisherman should receive the deposit back')
    })
  })

  describe('Arbitrating Indexing Disputes', () => {
    let disputeId: string

    beforeEach(async () => {
      // Approve dispute manager for dispute deposit
      await graphToken.connect(fisherman).approve(disputeManager.target, disputeDeposit)

      // Create dispute
      const poi = ethers.keccak256(ethers.toUtf8Bytes('test-poi'))
      const tx = await disputeManager.connect(fisherman).createIndexingDispute(allocationId, poi)
      const receipt = await tx.wait()

      // Get dispute ID from event
      const disputeCreatedEvent = receipt?.logs.find(
        log => log instanceof EventLog && log.fragment?.name === 'IndexingDisputeCreated',
      ) as EventLog
      disputeId = disputeCreatedEvent?.args[0]
    })

    it('should allow arbitrator to accept an indexing dispute', async () => {
      // Get fisherman's balance before accepting dispute
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Get indexer's provision before accepting dispute
      const provision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())

      // Get indexer stake snapshot
      const dispute = await disputeManager.disputes(disputeId)
      const tokensToSlash = dispute.stakeSnapshot / 10n

      // Accept dispute
      await disputeManager.connect(arbitrator).acceptDispute(disputeId, tokensToSlash)

      // Verify dispute status
      const updatedDispute = await disputeManager.disputes(disputeId)
      expect(updatedDispute.status).to.equal(1, 'Dispute status should be accepted')

      // Verify indexer's stake was slashed
      const updatedProvision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())
      expect(updatedProvision).to.equal(provision - tokensToSlash, 'Indexer stake should be slashed')

      // Verify fisherman got the deposit plus the reward
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      const fishermanReward = (tokensToSlash * fishermanRewardCut) / 1000000n
      const fishermanTotal = fishermanBalanceBefore + fishermanReward + disputeDeposit
      expect(fishermanBalance).to.equal(fishermanTotal, 'Fisherman balance should be increased by the reward and deposit')
    })

    it('should allow arbitrator to draw an indexing dispute', async () => {
      // Get fisherman's balance before drawing dispute
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Get indexer's provision before drawing dispute
      const provision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())

      // Draw dispute
      await disputeManager.connect(arbitrator).drawDispute(disputeId)

      // Verify dispute status
      const updatedDispute = await disputeManager.disputes(disputeId)
      expect(updatedDispute.status).to.equal(3, 'Dispute status should be drawn')

      // Verify indexer's provision was not affected
      const updatedProvision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())
      expect(updatedProvision).to.equal(provision, 'Indexer stake should not be affected')

      // Verify fisherman got the deposit back
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      expect(fishermanBalance).to.equal(fishermanBalanceBefore + disputeDeposit, 'Fisherman should receive the deposit back')
    })

    it('should allow arbitrator to reject an indexing dispute', async () => {
      // Get fisherman's balance before rejecting dispute
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Get indexer's provision before rejecting dispute
      const provision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())

      // Reject dispute
      await disputeManager.connect(arbitrator).rejectDispute(disputeId)

      // Verify dispute status
      const updatedDispute = await disputeManager.disputes(disputeId)
      expect(updatedDispute.status).to.equal(2, 'Dispute status should be rejected')

      // Verify indexer's provision was not affected
      const updatedProvision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())
      expect(updatedProvision).to.equal(provision, 'Indexer stake should not be affected')

      // Verify fisherman did not receive the deposit
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      expect(fishermanBalance).to.equal(fishermanBalanceBefore, 'Fisherman balance should not receive the deposit back')
    })

    it('should not allow non-arbitrator to accept an indexing dispute', async () => {
      // Get indexer stake snapshot
      const dispute = await disputeManager.disputes(disputeId)
      const tokensToSlash = dispute.stakeSnapshot / 10n

      // Attempt to accept dispute as fisherman
      await expect(
        disputeManager.connect(fisherman).acceptDispute(disputeId, tokensToSlash),
      ).to.be.revertedWithCustomError(disputeManager, 'DisputeManagerNotArbitrator')
    })

    it('should not allow non-arbitrator to draw an indexing dispute', async () => {
      // Attempt to draw dispute as fisherman
      await expect(
        disputeManager.connect(fisherman).drawDispute(disputeId),
      ).to.be.revertedWithCustomError(disputeManager, 'DisputeManagerNotArbitrator')
    })

    it('should not allow non-arbitrator to reject an indexing dispute', async () => {
      // Attempt to reject dispute as fisherman
      await expect(
        disputeManager.connect(fisherman).rejectDispute(disputeId),
      ).to.be.revertedWithCustomError(disputeManager, 'DisputeManagerNotArbitrator')
    })
  })
})

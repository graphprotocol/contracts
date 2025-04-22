import { ethers } from 'hardhat'
import { EventLog } from 'ethers'
import { expect } from 'chai'
import hre from 'hardhat'

import { DisputeManager, IGraphToken, SubgraphService } from '../../../../typechain-types'
import { generateAttestationData } from '@graphprotocol/toolshed'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { HorizonStaking } from '@graphprotocol/horizon'

import { indexers } from '../../../../tasks/test/fixtures/indexers'

describe('Query Conflict Disputes', () => {
  let disputeManager: DisputeManager
  let graphToken: IGraphToken
  let staking: HorizonStaking
  let subgraphService: SubgraphService

  let snapshotId: string
  let chainId: number

  // Test addresses
  let fisherman: HardhatEthersSigner
  let arbitrator: HardhatEthersSigner
  let indexer: HardhatEthersSigner
  let relatedIndexer: HardhatEthersSigner

  // Allocation variables
  let allocationPrivateKey: string
  let relatedAllocationPrivateKey: string
  let subgraphDeploymentId: string

  // Dispute manager variables
  let disputeDeposit: bigint
  let fishermanRewardCut: bigint
  let disputePeriod: bigint
  let disputeManagerAddress: string

  before(async () => {
    // Get contracts
    const graph = hre.graph()
    disputeManager = graph.subgraphService.contracts.DisputeManager
    graphToken = graph.horizon.contracts.GraphToken
    staking = graph.horizon.contracts.HorizonStaking
    subgraphService = graph.subgraphService.contracts.SubgraphService

    // Get signers
    arbitrator = await graph.accounts.getArbitrator()
    ;[fisherman] = await graph.accounts.getTestAccounts()

    // Get indexers
    const indexerFixture = indexers[0]
    indexer = await ethers.getSigner(indexerFixture.address)
    const relatedIndexerFixture = indexers[1]
    relatedIndexer = await ethers.getSigner(relatedIndexerFixture.address)

    // Get allocation
    const allocation = indexerFixture.allocations[0]
    allocationPrivateKey = allocation.allocationPrivateKey
    const relatedAllocation = relatedIndexerFixture.allocations[0]
    relatedAllocationPrivateKey = relatedAllocation.allocationPrivateKey
    subgraphDeploymentId = allocation.subgraphDeploymentID

    // Dispute manager variables
    disputeDeposit = await disputeManager.disputeDeposit()
    fishermanRewardCut = await disputeManager.fishermanRewardCut()
    disputePeriod = await disputeManager.disputePeriod()
    disputeManagerAddress = await disputeManager.getAddress()

    // Get chain ID
    chainId = Number((await ethers.provider.getNetwork()).chainId)
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
    it('should allow fisherman to create a query conflict dispute', async () => {
      // Create dispute
      const queryHash = ethers.keccak256(ethers.toUtf8Bytes('test-query'))
      const responseHash1 = ethers.keccak256(ethers.toUtf8Bytes('test-response-1'))
      const responseHash2 = ethers.keccak256(ethers.toUtf8Bytes('test-response-2'))

      // Create attestation data for both responses
      const attestationData1 = await generateAttestationData(
        queryHash,
        responseHash1,
        subgraphDeploymentId,
        allocationPrivateKey,
        disputeManagerAddress,
        chainId,
      )
      const attestationData2 = await generateAttestationData(
        queryHash,
        responseHash2,
        subgraphDeploymentId,
        relatedAllocationPrivateKey,
        disputeManagerAddress,
        chainId,
      )

      // Approve dispute manager for dispute deposit
      await graphToken.connect(fisherman).approve(disputeManager.target, disputeDeposit)

      // Create dispute
      const tx = await disputeManager.connect(fisherman).createQueryDisputeConflict(attestationData1, attestationData2)
      const receipt = await tx.wait()

      // Get dispute ID from event
      const disputeLinkedEvent = receipt?.logs.find(
        log => log instanceof EventLog && log.fragment?.name === 'DisputeLinked',
      ) as EventLog
      const disputeId = disputeLinkedEvent?.args[0]
      const relatedDisputeId = disputeLinkedEvent?.args[1]

      // Verify dispute was created
      const dispute = await disputeManager.disputes(disputeId)
      expect(dispute.indexer).to.equal(indexer.address, 'Indexer address mismatch')
      expect(dispute.fisherman).to.equal(fisherman.address, 'Fisherman address mismatch')
      expect(dispute.disputeType).to.equal(2, 'Dispute type should be query')
      expect(dispute.status).to.equal(4, 'Dispute status should be pending')

      // Verify related dispute was created
      const relatedDispute = await disputeManager.disputes(relatedDisputeId)
      expect(relatedDispute.indexer).to.equal(relatedIndexer.address, 'Related indexer address mismatch')
      expect(relatedDispute.fisherman).to.equal(fisherman.address, 'Related fisherman address mismatch')
      expect(relatedDispute.disputeType).to.equal(2, 'Related dispute type should be query')
      expect(relatedDispute.status).to.equal(4, 'Related dispute status should be pending')
    })

    it('should allow fisherman to cancel a query conflict dispute', async () => {
      // Create dispute
      const queryHash = ethers.keccak256(ethers.toUtf8Bytes('test-query'))
      const responseHash1 = ethers.keccak256(ethers.toUtf8Bytes('test-response-1'))
      const responseHash2 = ethers.keccak256(ethers.toUtf8Bytes('test-response-2'))

      // Create attestation data for both responses
      const attestationData1 = await generateAttestationData(
        queryHash,
        responseHash1,
        subgraphDeploymentId,
        allocationPrivateKey,
        disputeManagerAddress,
        chainId,
      )
      const attestationData2 = await generateAttestationData(
        queryHash,
        responseHash2,
        subgraphDeploymentId,
        relatedAllocationPrivateKey,
        disputeManagerAddress,
        chainId,
      )

      // Approve dispute manager for dispute deposit
      await graphToken.connect(fisherman).approve(disputeManager.target, disputeDeposit)

      // Create dispute
      const tx = await disputeManager.connect(fisherman).createQueryDisputeConflict(attestationData1, attestationData2)
      const receipt = await tx.wait()

      // Get dispute ID from event
      const disputeLinkedEvent = receipt?.logs.find(
        log => log instanceof EventLog && log.fragment?.name === 'DisputeLinked',
      ) as EventLog
      const disputeId = disputeLinkedEvent?.args[0]
      const relatedDisputeId = disputeLinkedEvent?.args[1]

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

      // Verify related dispute was canceled
      const updatedRelatedDispute = await disputeManager.disputes(relatedDisputeId)
      expect(updatedRelatedDispute.status).to.equal(5, 'Related dispute status should be canceled')

      // Verify fisherman got the deposit back
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      expect(fishermanBalance).to.equal(fishermanBalanceBefore + disputeDeposit, 'Fisherman should receive the deposit back')
    })
  })

  describe('Arbitrating Query Conflict Disputes', () => {
    let disputeId: string
    let relatedDisputeId: string

    beforeEach(async () => {
      // Create dispute
      const queryHash = ethers.keccak256(ethers.toUtf8Bytes('test-query'))
      const responseHash1 = ethers.keccak256(ethers.toUtf8Bytes('test-response-1'))
      const responseHash2 = ethers.keccak256(ethers.toUtf8Bytes('test-response-2'))

      // Create attestation data for both responses
      const attestationData1 = await generateAttestationData(
        queryHash,
        responseHash1,
        subgraphDeploymentId,
        allocationPrivateKey,
        disputeManagerAddress,
        chainId,
      )
      const attestationData2 = await generateAttestationData(
        queryHash,
        responseHash2,
        subgraphDeploymentId,
        relatedAllocationPrivateKey,
        disputeManagerAddress,
        chainId,
      )

      // Approve dispute manager for dispute deposit
      await graphToken.connect(fisherman).approve(disputeManager.target, disputeDeposit)

      // Create dispute
      const tx = await disputeManager.connect(fisherman).createQueryDisputeConflict(attestationData1, attestationData2)
      const receipt = await tx.wait()

      // Get dispute ID from event
      const disputeLinkedEvent = receipt?.logs.find(
        log => log instanceof EventLog && log.fragment?.name === 'DisputeLinked',
      ) as EventLog
      disputeId = disputeLinkedEvent?.args[0]
      relatedDisputeId = disputeLinkedEvent?.args[1]
    })

    it('should allow arbitrator to accept one of the query conflict disputes', async () => {
      // Get fisherman's balance before accepting dispute
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Get indexer's provision before accepting dispute
      const provision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())

      // Get indexer stake snapshot
      const dispute = await disputeManager.disputes(disputeId)
      const tokensToSlash = dispute.stakeSnapshot / 10n

      // Accept dispute with first response
      await disputeManager.connect(arbitrator).acceptDisputeConflict(disputeId, tokensToSlash, false, 0n)

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

    it('should allow arbitrator to accept both query conflict disputes', async () => {
      // Get fisherman's balance before accepting dispute
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Get indexer's provision before accepting dispute
      const provision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())
      const provisionRelated = await staking.getProviderTokensAvailable(relatedIndexer.address, await subgraphService.getAddress())

      // Get indexer stake snapshot
      const dispute = await disputeManager.disputes(disputeId)
      const relatedDispute = await disputeManager.disputes(relatedDisputeId)
      const tokensToSlash = dispute.stakeSnapshot / 10n
      const tokensToSlashRelated = relatedDispute.stakeSnapshot / 10n

      // Accept dispute with both responses
      await disputeManager.connect(arbitrator).acceptDisputeConflict(disputeId, tokensToSlash, true, tokensToSlashRelated)

      // Verify dispute status
      const updatedDispute = await disputeManager.disputes(disputeId)
      expect(updatedDispute.status).to.equal(1, 'Dispute status should be accepted')

      // Verify related dispute status
      const updatedRelatedDispute = await disputeManager.disputes(relatedDisputeId)
      expect(updatedRelatedDispute.status).to.equal(1, 'Related dispute status should be accepted')

      // Verify indexer's stake was slashed
      const updatedProvision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())
      expect(updatedProvision).to.equal(provision - tokensToSlash, 'Indexer stake should be slashed')

      // Verify related indexer's stake was slashed
      const updatedProvisionRelated = await staking.getProviderTokensAvailable(relatedIndexer.address, await subgraphService.getAddress())
      expect(updatedProvisionRelated).to.equal(provisionRelated - tokensToSlashRelated, 'Related indexer stake should be slashed')

      // Verify fisherman got the deposit plus the reward
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      const fishermanReward = ((tokensToSlash + tokensToSlashRelated) * fishermanRewardCut) / 1000000n
      const fishermanTotal = fishermanBalanceBefore + fishermanReward + disputeDeposit
      expect(fishermanBalance).to.equal(fishermanTotal, 'Fisherman balance should be increased by the reward and deposit')
    })

    it('should allow arbitrator to draw query conflict dispute', async () => {
      // Get fisherman's balance before drawing dispute
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Get indexer's provision before drawing disputes
      const provision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())
      const provisionRelated = await staking.getProviderTokensAvailable(relatedIndexer.address, await subgraphService.getAddress())

      // Draw dispute
      await disputeManager.connect(arbitrator).drawDispute(disputeId)

      // Verify dispute status
      const updatedDispute = await disputeManager.disputes(disputeId)
      expect(updatedDispute.status).to.equal(3, 'Dispute status should be drawn')

      // Verify related dispute status
      const updatedRelatedDispute = await disputeManager.disputes(relatedDisputeId)
      expect(updatedRelatedDispute.status).to.equal(3, 'Related dispute status should be drawn')

      // Verify indexer's provision was not affected
      const updatedProvision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())
      expect(updatedProvision).to.equal(provision, 'Indexer stake should not be affected')

      // Verify related indexer's provision was not affected
      const updatedProvisionRelated = await staking.getProviderTokensAvailable(relatedIndexer.address, await subgraphService.getAddress())
      expect(updatedProvisionRelated).to.equal(provisionRelated, 'Related indexer stake should not be affected')

      // Verify fisherman got the deposit back
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      expect(fishermanBalance).to.equal(fishermanBalanceBefore + disputeDeposit, 'Fisherman should receive the deposit back')
    })

    it('should not allow arbitrator to reject a query conflict dispute', async () => {
      // Attempt to reject dispute
      await expect(
        disputeManager.connect(arbitrator).rejectDispute(disputeId),
      ).to.be.revertedWithCustomError(disputeManager, 'DisputeManagerDisputeInConflict')
    })

    it('should not allow non-arbitrator to accept a query conflict dispute', async () => {
      // Get indexer stake snapshot
      const dispute = await disputeManager.disputes(disputeId)
      const tokensToSlash = dispute.stakeSnapshot / 10n

      // Attempt to accept dispute as fisherman
      await expect(
        disputeManager.connect(fisherman).acceptDispute(disputeId, tokensToSlash),
      ).to.be.revertedWithCustomError(disputeManager, 'DisputeManagerNotArbitrator')
    })

    it('should not allow non-arbitrator to draw a query conflict dispute', async () => {
      // Attempt to draw dispute as fisherman
      await expect(
        disputeManager.connect(fisherman).drawDispute(disputeId),
      ).to.be.revertedWithCustomError(disputeManager, 'DisputeManagerNotArbitrator')
    })
  })
})

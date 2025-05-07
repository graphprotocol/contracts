import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'
import { EventLog } from 'ethers'

import { DisputeManager, IGraphToken, SubgraphService } from '../../../typechain-types'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { HorizonStaking } from '@graphprotocol/horizon'
import { LegacyDisputeManager } from '@graphprotocol/toolshed/deployments'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'

import { indexers } from '../../../tasks/test/fixtures/indexers'

describe('Dispute Manager', () => {
  let disputeManager: DisputeManager
  let legacyDisputeManager: LegacyDisputeManager
  let graphToken: IGraphToken
  let staking: HorizonStaking
  let subgraphService: SubgraphService

  let snapshotId: string

  // Test addresses
  let governor: HardhatEthersSigner
  let fisherman: HardhatEthersSigner
  let arbitrator: HardhatEthersSigner
  let indexer: HardhatEthersSigner

  let disputeDeposit: bigint

  // Allocation variables
  let allocationId: string

  before(async () => {
    // Get contracts
    const graph = hre.graph()
    disputeManager = graph.subgraphService.contracts.DisputeManager
    legacyDisputeManager = graph.subgraphService.contracts.LegacyDisputeManager
    graphToken = graph.horizon.contracts.GraphToken
    staking = graph.horizon.contracts.HorizonStaking
    subgraphService = graph.subgraphService.contracts.SubgraphService

    // Get signers
    governor = await graph.accounts.getGovernor()
    arbitrator = await graph.accounts.getArbitrator()
    ;[fisherman] = await graph.accounts.getTestAccounts()

    // Get indexer
    const indexerFixture = indexers[0]
    indexer = await ethers.getSigner(indexerFixture.address)

    // Get allocation
    const allocation = indexerFixture.legacyAllocations[0]
    allocationId = allocation.allocationID

    // Get dispute deposit
    disputeDeposit = ethers.parseEther('10000')

    // Set GRT balance for fisherman
    await setGRTBalance(graph.provider, graphToken.target, fisherman.address, ethers.parseEther('1000000'))

    // Set arbitrator
    await legacyDisputeManager.connect(governor).setArbitrator(arbitrator.address)
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Legacy dispute type', () => {
    describe('Arbitrator', () => {
      it('should allow arbitrator to create and accept a legacy dispute on the new dispute manager after slashing on the legacy dispute manager', async () => {
        // Create an indexing dispute on legacy dispute manager
        await graphToken.connect(fisherman).approve(legacyDisputeManager.target, disputeDeposit)
        await legacyDisputeManager.connect(fisherman).createIndexingDispute(allocationId, disputeDeposit)
        const legacyDisputeId = ethers.solidityPackedKeccak256(['address'], [allocationId])

        // Accept the dispute on the legacy dispute manager
        await legacyDisputeManager.connect(arbitrator).acceptDispute(legacyDisputeId)

        // Get fisherman's balance before creating dispute
        const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

        // Get indexer's provision before creating dispute
        const provision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())

        // Create and accept legacy dispute using the same allocation ID
        const tokensToSlash = ethers.parseEther('100000')
        const tokensToReward = tokensToSlash / 2n
        await disputeManager.connect(arbitrator).createAndAcceptLegacyDispute(
          allocationId,
          fisherman.address,
          tokensToSlash,
          tokensToReward
        )

        // Get dispute ID from event
        const disputeId = ethers.solidityPackedKeccak256(
          ['address', 'string'],
          [allocationId, 'legacy']
        )

        // Verify dispute was created and accepted
        const dispute = await disputeManager.disputes(disputeId)
        expect(dispute.indexer).to.equal(indexer.address, 'Indexer address mismatch')
        expect(dispute.fisherman).to.equal(fisherman.address, 'Fisherman address mismatch')
        expect(dispute.disputeType).to.equal(3, 'Dispute type should be legacy')
        expect(dispute.status).to.equal(1, 'Dispute status should be accepted')

        // Verify indexer's stake was slashed
        const updatedProvision = await staking.getProviderTokensAvailable(indexer.address, await subgraphService.getAddress())
        expect(updatedProvision).to.equal(provision - tokensToSlash, 'Indexer stake should be slashed')

        // Verify fisherman got the reward
        const fishermanBalance = await graphToken.balanceOf(fisherman.address)
        expect(fishermanBalance).to.equal(fishermanBalanceBefore + tokensToReward, 'Fisherman balance should be increased by the reward')
      })

      it('should not allow creating a legacy dispute for non-existent allocation', async () => {
        const tokensToSlash = ethers.parseEther('1000')
        const tokensToReward = tokensToSlash / 2n
  
        // Attempt to create legacy dispute with non-existent allocation
        await expect(
          disputeManager.connect(arbitrator).createAndAcceptLegacyDispute(
            ethers.Wallet.createRandom().address,
            fisherman.address,
            tokensToSlash,
            tokensToReward
          )
        ).to.be.revertedWithCustomError(disputeManager, 'DisputeManagerIndexerNotFound')
      })
    })

    it('should not allow non-arbitrator to create a legacy dispute', async () => {
      const tokensToSlash = ethers.parseEther('1000')
      const tokensToReward = tokensToSlash / 2n

      // Attempt to create legacy dispute as fisherman
      await expect(
        disputeManager.connect(fisherman).createAndAcceptLegacyDispute(
          allocationId,
          fisherman.address,
          tokensToSlash,
          tokensToReward
        )
      ).to.be.revertedWithCustomError(disputeManager, 'DisputeManagerNotArbitrator')
    })
  })
})

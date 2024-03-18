import hre from 'hardhat'
import { expect } from 'chai'
import { constants } from 'ethers'
import { createAttestation, Receipt } from '@graphprotocol/common-ts'

import { DisputeManager } from '../../../build/types/DisputeManager'
import { EpochManager } from '../../../build/types/EpochManager'
import { GraphToken } from '../../../build/types/GraphToken'
import { IStaking } from '../../../build/types/IStaking'

import { NetworkFixture } from '../lib/fixtures'

import { createQueryDisputeID, Dispute, encodeAttestation, MAX_PPM } from './common'
import {
  deriveChannelKey,
  GraphNetworkContracts,
  helpers,
  randomHexBytes,
  toBN,
  toGRT,
} from '@graphprotocol/sdk'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const { HashZero } = constants

const NON_EXISTING_DISPUTE_ID = randomHexBytes()

describe('DisputeManager:Query', () => {
  let me: SignerWithAddress
  let governor: SignerWithAddress
  let arbitrator: SignerWithAddress
  let indexer: SignerWithAddress
  let indexer2: SignerWithAddress
  let rewardsDestination: SignerWithAddress
  let fisherman: SignerWithAddress
  let fisherman2: SignerWithAddress
  let assetHolder: SignerWithAddress

  const graph = hre.graph()
  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let disputeManager: DisputeManager
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: IStaking

  // Derive some channel keys for each indexer used to sign attestations
  const indexer1ChannelKey = deriveChannelKey()
  const indexer2ChannelKey = deriveChannelKey()

  // Test values
  const fishermanTokens = toGRT('100000')
  const fishermanDeposit = toGRT('1000')
  const indexerTokens = toGRT('100000')
  const indexerAllocatedTokens = toGRT('10000')
  const metadata = HashZero

  const poi = randomHexBytes()

  // Create an attesation receipt for the dispute
  const receipt: Receipt = {
    requestCID: randomHexBytes(),
    responseCID: randomHexBytes(),
    subgraphDeploymentID: randomHexBytes(),
  }
  let dispute: Dispute

  async function buildAttestation(receipt: Receipt, signer: string) {
    const attestation = await createAttestation(
      signer,
      graph.chainId,
      disputeManager.address,
      receipt,
      '0',
    )
    return attestation
  }

  async function calculateSlashConditions(indexerAddress: string) {
    const qrySlashingPercentage = await disputeManager.qrySlashingPercentage()
    const fishermanRewardPercentage = await disputeManager.fishermanRewardPercentage()
    const stakeAmount = await staking.getIndexerStakedTokens(indexerAddress)
    const slashAmount = stakeAmount.mul(qrySlashingPercentage).div(toBN(MAX_PPM))
    const rewardsAmount = slashAmount.mul(fishermanRewardPercentage).div(toBN(MAX_PPM))

    return { slashAmount, rewardsAmount }
  }

  async function setupIndexers() {
    // Dispute manager is allowed to slash
    await staking.connect(governor).setSlasher(disputeManager.address, true)

    // Stake
    const indexerList = [
      {
        account: indexer,
        allocationID: indexer1ChannelKey.address,
        channelKey: indexer1ChannelKey,
      },
      {
        account: indexer2,
        allocationID: indexer2ChannelKey.address,
        channelKey: indexer2ChannelKey,
      },
    ]
    for (const activeIndexer of indexerList) {
      const { channelKey, allocationID, account: indexerAccount } = activeIndexer

      // Give some funds to the indexer
      await grt.connect(governor).mint(indexerAccount.address, indexerTokens)
      await grt.connect(indexerAccount).approve(staking.address, indexerTokens)

      // Indexer stake funds
      await staking.connect(indexerAccount).stake(indexerTokens)
      await staking
        .connect(indexerAccount)
        .allocateFrom(
          indexerAccount.address,
          dispute.receipt.subgraphDeploymentID,
          indexerAllocatedTokens,
          allocationID,
          metadata,
          await channelKey.generateProof(indexerAccount.address),
        )
    }
  }

  before(async function () {
    [me, indexer, indexer2, fisherman, fisherman2, assetHolder, rewardsDestination]
      = await graph.getTestAccounts()
    ;({ governor, arbitrator } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    disputeManager = contracts.DisputeManager
    epochManager = contracts.EpochManager
    grt = contracts.GraphToken as GraphToken
    staking = contracts.Staking as IStaking

    // Give some funds to the fisherman
    for (const dst of [fisherman, fisherman2]) {
      await grt.connect(governor).mint(dst.address, fishermanTokens)
      await grt.connect(dst).approve(disputeManager.address, fishermanTokens)
    }

    // Create an attestation
    const attestation = await buildAttestation(receipt, indexer1ChannelKey.privKey)

    // Create dispute data
    dispute = {
      id: createQueryDisputeID(attestation, indexer.address, fisherman.address),
      attestation,
      encodedAttestation: encodeAttestation(attestation),
      indexerAddress: indexer.address,
      receipt,
    }
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('disputes', function () {
    it('reject create a dispute if attestation does not refer to valid indexer', async function () {
      // Create dispute
      const tx = disputeManager
        .connect(fisherman)
        .createQueryDispute(dispute.encodedAttestation, fishermanDeposit)
      await expect(tx).revertedWith('Indexer cannot be found for the attestation')
    })

    it('reject create a dispute if indexer below stake', async function () {
      // This tests reproduce the case when someones present a dispute for
      // an indexer that is under the minimum required staked amount

      const indexerCollectedTokens = toGRT('10')

      // Give some funds to the indexer
      await grt.connect(governor).mint(indexer.address, indexerTokens)
      await grt.connect(indexer).approve(staking.address, indexerTokens)

      // Give some funds to the channel
      await grt.connect(governor).mint(assetHolder.address, indexerCollectedTokens)
      await grt.connect(assetHolder).approve(staking.address, indexerCollectedTokens)

      // Set the thawing period to zero to make the test easier
      await staking.connect(governor).setThawingPeriod(toBN('1'))

      // Indexer stake funds, allocate, close allocation, unstake and withdraw the stake fully
      await staking.connect(indexer).stake(indexerTokens)
      const tx1 = await staking
        .connect(indexer)
        .allocateFrom(
          indexer.address,
          dispute.receipt.subgraphDeploymentID,
          indexerAllocatedTokens,
          indexer1ChannelKey.address,
          metadata,
          await indexer1ChannelKey.generateProof(indexer.address),
        )
      const receipt1 = await tx1.wait()
      const event1 = staking.interface.parseLog(receipt1.logs[0]).args
      await helpers.mineEpoch(epochManager) // wait the required one epoch to close allocation
      // set rewards destination so collected query fees are not added to indexer balance
      await staking.connect(indexer).setRewardsDestination(rewardsDestination.address)
      await staking.connect(assetHolder).collect(indexerCollectedTokens, event1.allocationID)
      await staking.connect(indexer).closeAllocation(event1.allocationID, poi)
      await staking.connect(indexer).unstake(indexerTokens)
      await helpers.mine() // pass thawing period
      await staking.connect(indexer).withdraw()

      // Create dispute
      const tx = disputeManager
        .connect(fisherman)
        .createQueryDispute(dispute.encodedAttestation, fishermanDeposit)
      await expect(tx).revertedWith('Dispute indexer has no stake')
    })

    context('> when indexer is staked', function () {
      beforeEach(async function () {
        await setupIndexers()
      })

      describe('create dispute', function () {
        it('reject fisherman deposit below minimum required', async function () {
          // Minimum deposit a fisherman is required to do should be >= reward
          const minimumDeposit = await disputeManager.minimumDeposit()
          const belowMinimumDeposit = minimumDeposit.sub(toBN('1'))

          // Create invalid dispute as deposit is below minimum
          const tx = disputeManager
            .connect(fisherman)
            .createQueryDispute(dispute.encodedAttestation, belowMinimumDeposit)
          await expect(tx).revertedWith('Dispute deposit is under minimum required')
        })

        it('should create a dispute', async function () {
          // Create dispute
          const tx = disputeManager
            .connect(fisherman)
            .createQueryDispute(dispute.encodedAttestation, fishermanDeposit)
          await expect(tx)
            .emit(disputeManager, 'QueryDisputeCreated')
            .withArgs(
              dispute.id,
              dispute.indexerAddress,
              fisherman.address,
              fishermanDeposit,
              dispute.receipt.subgraphDeploymentID,
              dispute.encodedAttestation,
            )
        })
      })

      describe('accept a dispute', function () {
        it('reject to accept a non-existing dispute', async function () {
          const tx = disputeManager.connect(arbitrator).acceptDispute(NON_EXISTING_DISPUTE_ID)
          await expect(tx).revertedWith('Dispute does not exist')
        })
      })

      describe('reject a dispute', function () {
        it('reject to reject a non-existing dispute', async function () {
          const tx = disputeManager.connect(arbitrator).rejectDispute(NON_EXISTING_DISPUTE_ID)
          await expect(tx).revertedWith('Dispute does not exist')
        })
      })

      describe('draw a dispute', function () {
        it('reject to draw a non-existing dispute', async function () {
          const tx = disputeManager.connect(arbitrator).drawDispute(NON_EXISTING_DISPUTE_ID)
          await expect(tx).revertedWith('Dispute does not exist')
        })
      })

      context('> when dispute is created', function () {
        beforeEach(async function () {
          // Create dispute
          await disputeManager
            .connect(fisherman)
            .createQueryDispute(dispute.encodedAttestation, fishermanDeposit)
        })

        describe('create a dispute', function () {
          it('should create dispute if receipt is equal but for other indexer', async function () {
            // Create dispute (same receipt but different indexer)
            const attestation = await buildAttestation(receipt, indexer2ChannelKey.privKey)
            const newDispute: Dispute = {
              id: createQueryDisputeID(attestation, indexer2.address, fisherman.address),
              attestation,
              encodedAttestation: encodeAttestation(attestation),
              indexerAddress: indexer2.address,
              receipt,
            }

            // Create dispute
            const tx = disputeManager
              .connect(fisherman)
              .createQueryDispute(newDispute.encodedAttestation, fishermanDeposit)
            await expect(tx)
              .emit(disputeManager, 'QueryDisputeCreated')
              .withArgs(
                newDispute.id,
                newDispute.indexerAddress,
                fisherman.address,
                fishermanDeposit,
                newDispute.receipt.subgraphDeploymentID,
                newDispute.encodedAttestation,
              )
          })

          it('should create dispute as long as it is from different fisherman', async function () {
            await disputeManager
              .connect(fisherman2)
              .createQueryDispute(dispute.encodedAttestation, fishermanDeposit)
          })

          it('reject create duplicated dispute', async function () {
            const tx = disputeManager
              .connect(fisherman)
              .createQueryDispute(dispute.encodedAttestation, fishermanDeposit)
            await expect(tx).revertedWith('Dispute already created')
          })
        })

        describe('accept a dispute', function () {
          it('reject to accept a dispute if not the arbitrator', async function () {
            const tx = disputeManager.connect(me).acceptDispute(dispute.id)
            await expect(tx).revertedWith('Caller is not the Arbitrator')
          })

          it('reject to accept a dispute if not slasher', async function () {
            // Dispute manager is not allowed to slash
            await staking.connect(governor).setSlasher(disputeManager.address, false)

            // Perform transaction (accept)
            const tx = disputeManager.connect(arbitrator).acceptDispute(dispute.id)
            await expect(tx).revertedWith('!slasher')
          })

          it('reject to accept a dispute if zero tokens to slash', async function () {
            await disputeManager.connect(governor).setSlashingPercentage(toBN('0'), toBN('0'))
            const tx = disputeManager.connect(arbitrator).acceptDispute(dispute.id)
            await expect(tx).revertedWith('Dispute has zero tokens to slash')
          })

          it('should resolve dispute, slash indexer and reward the fisherman', async function () {
            // Before state
            const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
            const beforeFishermanBalance = await grt.balanceOf(fisherman.address)
            const beforeTotalSupply = await grt.totalSupply()

            // Calculations
            const { slashAmount, rewardsAmount } = await calculateSlashConditions(indexer.address)

            // Perform transaction (accept)
            const tx = disputeManager.connect(arbitrator).acceptDispute(dispute.id)
            await expect(tx)
              .emit(disputeManager, 'DisputeAccepted')
              .withArgs(
                dispute.id,
                dispute.indexerAddress,
                fisherman.address,
                fishermanDeposit.add(rewardsAmount),
              )

            // After state
            const afterFishermanBalance = await grt.balanceOf(fisherman.address)
            const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
            const afterTotalSupply = await grt.totalSupply()

            // Fisherman reward properly assigned + deposit returned
            expect(afterFishermanBalance).eq(
              beforeFishermanBalance.add(fishermanDeposit).add(rewardsAmount),
            )
            // Indexer slashed
            expect(afterIndexerStake).eq(beforeIndexerStake.sub(slashAmount))
            // Slashed funds burned
            const tokensToBurn = slashAmount.sub(rewardsAmount)
            expect(afterTotalSupply).eq(beforeTotalSupply.sub(tokensToBurn))
          })
        })

        describe('reject a dispute', function () {
          it('reject to reject a dispute if not the arbitrator', async function () {
            const tx = disputeManager.connect(me).rejectDispute(dispute.id)
            await expect(tx).revertedWith('Caller is not the Arbitrator')
          })

          it('should reject a dispute and burn deposit', async function () {
            // Before state
            const beforeFishermanBalance = await grt.balanceOf(fisherman.address)
            const beforeTotalSupply = await grt.totalSupply()

            // Perform transaction (reject)
            const tx = disputeManager.connect(arbitrator).rejectDispute(dispute.id)
            await expect(tx)
              .emit(disputeManager, 'DisputeRejected')
              .withArgs(dispute.id, dispute.indexerAddress, fisherman.address, fishermanDeposit)

            // After state
            const afterFishermanBalance = await grt.balanceOf(fisherman.address)
            const afterTotalSupply = await grt.totalSupply()

            // No change in fisherman balance
            expect(afterFishermanBalance).eq(beforeFishermanBalance)
            // Burn fisherman deposit
            const burnedTokens = fishermanDeposit
            expect(afterTotalSupply).eq(beforeTotalSupply.sub(burnedTokens))
          })
        })

        describe('draw a dispute', function () {
          it('reject to draw a dispute if not the arbitrator', async function () {
            const tx = disputeManager.connect(me).drawDispute(dispute.id)
            await expect(tx).revertedWith('Caller is not the Arbitrator')
          })

          it('should draw a dispute and return deposit', async function () {
            // Before state
            const beforeFishermanBalance = await grt.balanceOf(fisherman.address)

            // Perform transaction (draw)
            const tx = disputeManager.connect(arbitrator).drawDispute(dispute.id)
            await expect(tx)
              .emit(disputeManager, 'DisputeDrawn')
              .withArgs(dispute.id, dispute.indexerAddress, fisherman.address, fishermanDeposit)

            // Fisherman should see the deposit returned
            const afterFishermanBalance = await grt.balanceOf(fisherman.address)
            expect(afterFishermanBalance).eq(beforeFishermanBalance.add(fishermanDeposit))
          })
        })
      })
    })
  })

  describe('disputes for conflicting attestations', function () {
    async function getIndependentAttestations() {
      const attestation1 = await buildAttestation(receipt, indexer1ChannelKey.privKey)
      const attestation2 = await buildAttestation(receipt, indexer2ChannelKey.privKey)
      return [attestation1, attestation2]
    }

    async function getConflictingAttestations() {
      const receipt1 = receipt
      const receipt2 = { ...receipt1, responseCID: randomHexBytes() }

      const attestation1 = await buildAttestation(receipt1, indexer1ChannelKey.privKey)
      const attestation2 = await buildAttestation(receipt2, indexer2ChannelKey.privKey)
      return [attestation1, attestation2]
    }

    beforeEach(async function () {
      await setupIndexers()
    })

    it('reject if attestations are not in conflict', async function () {
      const [attestation1, attestation2] = await getIndependentAttestations()
      const tx = disputeManager
        .connect(fisherman)
        .createQueryDisputeConflict(
          encodeAttestation(attestation1),
          encodeAttestation(attestation2),
        )
      await expect(tx).revertedWith('Attestations must be in conflict')
    })

    it('should create dispute', async function () {
      const [attestation1, attestation2] = await getConflictingAttestations()
      const dID1 = createQueryDisputeID(attestation1, indexer.address, fisherman.address)
      const dID2 = createQueryDisputeID(attestation2, indexer2.address, fisherman.address)
      const tx = disputeManager
        .connect(fisherman)
        .createQueryDisputeConflict(
          encodeAttestation(attestation1),
          encodeAttestation(attestation2),
        )
      await expect(tx).emit(disputeManager, 'DisputeLinked').withArgs(dID1, dID2)

      // Test state
      const dispute1 = await disputeManager.disputes(dID1)
      const dispute2 = await disputeManager.disputes(dID2)
      expect(dispute1.relatedDisputeID).eq(dID2)
      expect(dispute2.relatedDisputeID).eq(dID1)
    })

    async function setupConflictingDisputes() {
      const [attestation1, attestation2] = await getConflictingAttestations()
      const dID1 = createQueryDisputeID(attestation1, indexer.address, fisherman.address)
      const dID2 = createQueryDisputeID(attestation2, indexer2.address, fisherman.address)
      const tx = disputeManager
        .connect(fisherman)
        .createQueryDisputeConflict(
          encodeAttestation(attestation1),
          encodeAttestation(attestation2),
        )
      await tx
      return [dID1, dID2]
    }

    it('should accept one dispute and resolve the related dispute', async function () {
      // Setup
      const [dID1, dID2] = await setupConflictingDisputes()
      // Do
      await disputeManager.connect(arbitrator).acceptDispute(dID1)
      // Check
      const mainDispute = await disputeManager.disputes(dID1)
      expect(mainDispute.status).to.eq(1) // 1 = DisputeStatus.Accepted
      const relatedDispute = await disputeManager.disputes(dID2)
      expect(relatedDispute.status).to.eq(2) // 2 = DisputeStatus.Rejected
    })

    it('should not allow to reject, user need to accept the related dispute ID to reject it', async function () {
      // Setup
      const [dID1] = await setupConflictingDisputes()
      // Do
      const tx = disputeManager.connect(arbitrator).rejectDispute(dID1)
      await expect(tx).revertedWith(
        'Dispute for conflicting attestation, must accept the related ID to reject',
      )
    })

    it('should draw one dispute and resolve the related dispute', async function () {
      // Setup
      const [dID1, dID2] = await setupConflictingDisputes()
      // Do
      await disputeManager.connect(arbitrator).drawDispute(dID1)
      // Check
      const relatedDispute = await disputeManager.disputes(dID2)
      expect(relatedDispute.status).not.eq(4) // 4 = DisputeStatus.Pending
    })
  })
})

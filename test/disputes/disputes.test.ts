import { expect, use } from 'chai'
import { utils } from 'ethers'
import { solidity } from 'ethereum-waffle'
import { attestations } from '@graphprotocol/common-ts'

import { DisputeManager } from '../../build/typechain/contracts/DisputeManager'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'
import {
  advanceToNextEpoch,
  defaults,
  getAccounts,
  getChainID,
  randomHexBytes,
  toBN,
  toGRT,
  Account,
} from '../lib/testHelpers'

use(solidity)

const { defaultAbiCoder: abi, arrayify, concat, hexlify, solidityKeccak256 } = utils

const MAX_PPM = 1000000
const NON_EXISTING_DISPUTE_ID = randomHexBytes()

interface Dispute {
  id: string
  attestation: attestations.Attestation
  encodedAttestation: string
  indexerAddress: string
  receipt: attestations.Receipt
}

function createDisputeID(attestation: attestations.Attestation, indexerAddress: string) {
  return solidityKeccak256(
    ['bytes32', 'bytes32', 'bytes32', 'address'],
    [
      attestation.requestCID,
      attestation.responseCID,
      attestation.subgraphDeploymentID,
      indexerAddress,
    ],
  )
}

function encodeAttestation(attestation: attestations.Attestation): string {
  const data = arrayify(
    abi.encode(
      ['bytes32', 'bytes32', 'bytes32'],
      [attestation.requestCID, attestation.responseCID, attestation.subgraphDeploymentID],
    ),
  )
  const sig = concat([
    arrayify(hexlify(attestation.v)),
    arrayify(attestation.r),
    arrayify(attestation.s),
  ])
  return hexlify(concat([data, sig]))
}

describe('DisputeManager:Disputes', async () => {
  let me: Account
  let other: Account
  let governor: Account
  let arbitrator: Account
  let indexer: Account
  let fisherman: Account
  let otherIndexer: Account
  let channelProxy: Account

  let fixture: NetworkFixture

  let disputeManager: DisputeManager
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

  // Channel keys for account #4
  const indexerChannelPrivKey = '0xe9696cbe81b09b796be29055c8694eb422710940b44934b3a1d21c1ca0a03e9a'
  const indexerChannelPubKey =
    '0x04417b6be970480e74a55182ee04279fdffa7431002af2150750d367999a59abead903fbd23c0da7bb4233fdbccd732a2f561e66460718b4c50084e736c1601555'
  // Channel keys for account #6
  const otherIndexerChannelPrivKey =
    '0xb560ebb22d7369c8ffeb9aec92930adfab16054542eadc76de826bc7db6390c2'
  const otherIndexerChannelPubKey =
    '0x0447b5891c07679d40d6dfd3c4f8e1974e068da36ac76a6507dbaf5e432b879b3d4cd8c950b0df035e621f5a55b91a224ecdaef8cc8e6bb8cd8afff4a74c1904cd'

  // Test values
  const fishermanTokens = toGRT('100000')
  const fishermanDeposit = toGRT('1000')
  const indexerTokens = toGRT('100000')
  const indexerAllocatedTokens = toGRT('10000')

  // Create an attesation receipt for the dispute
  const receipt: attestations.Receipt = {
    requestCID: randomHexBytes(),
    responseCID: randomHexBytes(),
    subgraphDeploymentID: randomHexBytes(),
  }
  let dispute: Dispute

  before(async function () {
    ;[
      me,
      other,
      governor,
      arbitrator,
      indexer,
      fisherman,
      otherIndexer,
      channelProxy,
    ] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ disputeManager, epochManager, grt, staking } = await fixture.load(
      governor.signer,
      other.signer,
      arbitrator.signer,
    ))

    // Give some funds to the fisherman
    await grt.connect(governor.signer).mint(fisherman.address, fishermanTokens)
    await grt.connect(fisherman.signer).approve(disputeManager.address, fishermanTokens)

    // Create an attestation
    const attestation = await attestations.createAttestation(
      indexerChannelPrivKey,
      await getChainID(),
      disputeManager.address,
      receipt,
    )

    // Create dispute data
    dispute = {
      id: createDisputeID(attestation, indexer.address),
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

  describe('dispute lifecycle', function () {
    it('reject create a dispute if attestation does not refer to valid indexer', async function () {
      // Create dispute
      const tx = disputeManager
        .connect(fisherman.signer)
        .createDispute(dispute.encodedAttestation, fishermanDeposit)
      await expect(tx).revertedWith('Indexer cannot be found for the attestation')
    })

    it('reject create a dispute if indexer has no stake', async function () {
      // This tests reproduce the case when someones present a dispute after
      // an indexer removed his stake completely and find nothing to slash

      const indexerTokens = toGRT('100000')
      const indexerAllocatedTokens = toGRT('10000')
      const indexerSettledTokens = toGRT('10')

      // Give some funds to the indexer
      await grt.connect(governor.signer).mint(indexer.address, indexerTokens)
      await grt.connect(indexer.signer).approve(staking.address, indexerTokens)

      // Give some funds to the channel
      await grt.connect(governor.signer).mint(channelProxy.address, indexerSettledTokens)
      await grt.connect(channelProxy.signer).approve(staking.address, indexerSettledTokens)

      // Set the thawing period to zero to make the test easier
      await staking.connect(governor.signer).setThawingPeriod(toBN('0'))

      // Indexer stake funds, allocate, settle, unstake and withdraw the stake fully
      await staking.connect(indexer.signer).stake(indexerTokens)
      const tx1 = await staking
        .connect(indexer.signer)
        .allocate(
          dispute.receipt.subgraphDeploymentID,
          indexerAllocatedTokens,
          indexerChannelPubKey,
          channelProxy.address,
          toBN('0'),
        )
      const receipt1 = await tx1.wait()
      const event1 = staking.interface.parseLog(receipt1.logs[0]).args
      await advanceToNextEpoch(epochManager) // wait the required one epoch to settle
      await staking.connect(channelProxy.signer).collect(indexerSettledTokens, event1.channelID)
      await staking.connect(indexer.signer).settle(event1.channelID)
      await staking.connect(indexer.signer).unstake(indexerTokens)
      await staking.connect(indexer.signer).withdraw() // no thawing period so we are good

      // Create dispute
      const tx = disputeManager
        .connect(fisherman.signer)
        .createDispute(dispute.encodedAttestation, fishermanDeposit)
      await expect(tx).revertedWith('Dispute has no stake by the indexer')
    })

    context('> when indexer has staked', function () {
      beforeEach(async function () {
        // Dispute manager is allowed to slash
        await staking.connect(governor.signer).setSlasher(disputeManager.address, true)

        // Stake
        const indexerList = [
          { wallet: indexer, pubKey: indexerChannelPubKey },
          { wallet: otherIndexer, pubKey: otherIndexerChannelPubKey },
        ]
        for (const activeIndexer of indexerList) {
          const indexerWallet = activeIndexer.wallet
          const indexerPubKey = activeIndexer.pubKey

          // Give some funds to the indexer
          await grt.connect(governor.signer).mint(indexerWallet.address, indexerTokens)
          await grt.connect(indexerWallet.signer).approve(staking.address, indexerTokens)

          // Indexer stake funds
          await staking.connect(indexerWallet.signer).stake(indexerTokens)
          await staking
            .connect(indexerWallet.signer)
            .allocate(
              dispute.receipt.subgraphDeploymentID,
              indexerAllocatedTokens,
              indexerPubKey,
              channelProxy.address,
              toBN('0'),
            )
        }
      })

      describe('reward calculation', function () {
        it('should calculate the reward for a stake', async function () {
          const stakedAmount = indexerTokens
          const trueReward = stakedAmount
            .mul(defaults.dispute.slashingPercentage)
            .div(toBN(MAX_PPM))
            .mul(defaults.dispute.fishermanRewardPercentage)
            .div(toBN(MAX_PPM))
          const funcReward = await disputeManager.getTokensToReward(indexer.address)
          expect(funcReward).eq(trueReward.toString())
        })
      })

      describe('create dispute', function () {
        it('reject fisherman deposit below minimum required', async function () {
          // Minimum deposit a fisherman is required to do should be >= reward
          const minimumDeposit = await disputeManager.minimumDeposit()
          const belowMinimumDeposit = minimumDeposit.sub(toBN('1'))

          // Create invalid dispute as deposit is below minimum
          const tx = disputeManager
            .connect(fisherman.signer)
            .createDispute(dispute.encodedAttestation, belowMinimumDeposit)
          await expect(tx).revertedWith('Dispute deposit is under minimum required')
        })

        it('should create a dispute', async function () {
          // Create dispute
          const tx = disputeManager
            .connect(fisherman.signer)
            .createDispute(dispute.encodedAttestation, fishermanDeposit)
          await expect(tx)
            .emit(disputeManager, 'DisputeCreated')
            .withArgs(
              dispute.id,
              dispute.receipt.subgraphDeploymentID,
              dispute.indexerAddress,
              fisherman.address,
              fishermanDeposit,
              dispute.encodedAttestation,
            )
        })
      })

      describe('accept a dispute', function () {
        it('reject to accept a non-existing dispute', async function () {
          const tx = disputeManager
            .connect(arbitrator.signer)
            .acceptDispute(NON_EXISTING_DISPUTE_ID)
          await expect(tx).revertedWith('Dispute does not exist')
        })
      })

      describe('reject a dispute', function () {
        it('reject to reject a non-existing dispute', async function () {
          const tx = disputeManager
            .connect(arbitrator.signer)
            .rejectDispute(NON_EXISTING_DISPUTE_ID)
          await expect(tx).revertedWith('Dispute does not exist')
        })
      })

      describe('draw a dispute', function () {
        it('reject to draw a non-existing dispute', async function () {
          const tx = disputeManager.connect(arbitrator.signer).drawDispute(NON_EXISTING_DISPUTE_ID)
          await expect(tx).revertedWith('Dispute does not exist')
        })
      })

      context('> when dispute is created', function () {
        beforeEach(async function () {
          // Create dispute
          await disputeManager
            .connect(fisherman.signer)
            .createDispute(dispute.encodedAttestation, fishermanDeposit)
        })

        describe('create a dispute', function () {
          it('should create dispute if receipt is equal but for other indexer', async function () {
            // Create dispute (same receipt but different indexer)
            const attestation = await attestations.createAttestation(
              otherIndexerChannelPrivKey,
              await getChainID(),
              disputeManager.address,
              receipt,
            )
            const newDispute: Dispute = {
              id: createDisputeID(attestation, otherIndexer.address),
              attestation,
              encodedAttestation: encodeAttestation(attestation),
              indexerAddress: otherIndexer.address,
              receipt,
            }

            // Create dispute
            const tx = disputeManager
              .connect(fisherman.signer)
              .createDispute(newDispute.encodedAttestation, fishermanDeposit)
            await expect(tx)
              .emit(disputeManager, 'DisputeCreated')
              .withArgs(
                newDispute.id,
                newDispute.receipt.subgraphDeploymentID,
                newDispute.indexerAddress,
                fisherman.address,
                fishermanDeposit,
                newDispute.encodedAttestation,
              )
          })

          it('reject create duplicated dispute', async function () {
            const tx = disputeManager
              .connect(fisherman.signer)
              .createDispute(dispute.encodedAttestation, fishermanDeposit)
            await expect(tx).revertedWith('Dispute already created')
          })
        })

        describe('accept a dispute', function () {
          it('reject to accept a dispute if not the arbitrator', async function () {
            const tx = disputeManager.connect(me.signer).acceptDispute(dispute.id)
            await expect(tx).revertedWith('Caller is not the Arbitrator')
          })

          it('reject to accept a dispute if not slasher', async function () {
            // Dispute manager is not allowed to slash
            await staking.connect(governor.signer).setSlasher(disputeManager.address, false)

            // Perform transaction (accept)
            const tx = disputeManager.connect(arbitrator.signer).acceptDispute(dispute.id)
            await expect(tx).revertedWith('Caller is not a Slasher')
          })

          it('reject to accept a dispute if zero tokens to slash', async function () {
            await disputeManager.connect(governor.signer).setSlashingPercentage(toBN('0'))
            const tx = disputeManager.connect(arbitrator.signer).acceptDispute(dispute.id)
            await expect(tx).revertedWith('Dispute has zero tokens to slash')
          })

          it('should resolve dispute, slash indexer and reward the fisherman', async function () {
            // Before state
            const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
            const beforeFishermanBalance = await grt.balanceOf(fisherman.address)
            const beforeTotalSupply = await grt.totalSupply()

            // Calculations
            const tokensToSlash = await disputeManager.getTokensToSlash(indexer.address)
            const reward = await disputeManager.getTokensToReward(indexer.address)

            // Perform transaction (accept)
            const tx = disputeManager.connect(arbitrator.signer).acceptDispute(dispute.id)
            await expect(tx)
              .emit(disputeManager, 'DisputeAccepted')
              .withArgs(
                dispute.id,
                dispute.receipt.subgraphDeploymentID,
                dispute.indexerAddress,
                fisherman.address,
                fishermanDeposit.add(reward),
              )

            // After state
            const afterFishermanBalance = await grt.balanceOf(fisherman.address)
            const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
            const afterTotalSupply = await grt.totalSupply()

            // Fisherman reward properly assigned + deposit returned
            expect(afterFishermanBalance).eq(
              beforeFishermanBalance.add(fishermanDeposit).add(reward),
            )
            // Indexer slashed
            expect(afterIndexerStake).eq(beforeIndexerStake.sub(tokensToSlash))
            // Slashed funds burned
            const tokensToBurn = tokensToSlash.sub(reward)
            expect(afterTotalSupply).eq(beforeTotalSupply.sub(tokensToBurn))
          })
        })

        describe('reject a dispute', async function () {
          it('reject to reject a dispute if not the arbitrator', async function () {
            const tx = disputeManager.connect(me.signer).rejectDispute(dispute.id)
            await expect(tx).revertedWith('Caller is not the Arbitrator')
          })

          it('should reject a dispute and burn deposit', async function () {
            // Before state
            const beforeFishermanBalance = await grt.balanceOf(fisherman.address)
            const beforeTotalSupply = await grt.totalSupply()

            // Perform transaction (reject)
            const tx = disputeManager.connect(arbitrator.signer).rejectDispute(dispute.id)
            await expect(tx)
              .emit(disputeManager, 'DisputeRejected')
              .withArgs(
                dispute.id,
                dispute.receipt.subgraphDeploymentID,
                dispute.indexerAddress,
                fisherman.address,
                fishermanDeposit,
              )

            // After state
            const afterTishermanBalance = await grt.balanceOf(fisherman.address)
            const afterTotalSupply = await grt.totalSupply()

            // No change in fisherman balance
            expect(afterTishermanBalance).eq(beforeFishermanBalance)
            // Burn fisherman deposit
            const burnedTokens = fishermanDeposit
            expect(afterTotalSupply).eq(beforeTotalSupply.sub(burnedTokens))
          })
        })

        describe('draw a dispute', async function () {
          it('reject to draw a dispute if not the arbitrator', async function () {
            const tx = disputeManager.connect(me.signer).drawDispute(dispute.id)
            await expect(tx).revertedWith('Caller is not the Arbitrator')
          })

          it('should draw a dispute and return deposit', async function () {
            // Before state
            const beforeFishermanBalance = await grt.balanceOf(fisherman.address)

            // Perform transaction (draw)
            const tx = disputeManager.connect(arbitrator.signer).drawDispute(dispute.id)
            await expect(tx)
              .emit(disputeManager, 'DisputeDrawn')
              .withArgs(
                dispute.id,
                dispute.receipt.subgraphDeploymentID,
                dispute.indexerAddress,
                fisherman.address,
                fishermanDeposit,
              )

            // Fisherman should see the deposit returned
            const afterFishermanBalance = await grt.balanceOf(fisherman.address)
            expect(afterFishermanBalance).eq(beforeFishermanBalance.add(fishermanDeposit))
          })
        })
      })
    })
  })
})

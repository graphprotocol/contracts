import { expect, use } from 'chai'
import { constants, utils } from 'ethers'
import { solidity } from 'ethereum-waffle'
import { attestations } from '@graphprotocol/common-ts'

import { DisputeManager } from '../build/typechain/contracts/DisputeManager'
import { EpochManager } from '../build/typechain/contracts/EpochManager'
import { GraphToken } from '../build/typechain/contracts/GraphToken'
import { Staking } from '../build/typechain/contracts/Staking'

import * as deployment from './lib/deployment'
import {
  advanceBlockTo,
  defaults,
  getChainID,
  randomHexBytes,
  latestBlock,
  provider,
  toBN,
  toGRT,
} from './lib/testHelpers'

use(solidity)

const { AddressZero } = constants
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

describe('Disputes', async () => {
  const [
    me,
    other,
    governor,
    arbitrator,
    indexer,
    fisherman,
    otherIndexer,
    channelProxy,
  ] = provider().getWallets()

  let epochManager: EpochManager
  let disputeManager: DisputeManager
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

  // Create an attesation receipt for the dispute
  const receipt: attestations.Receipt = {
    requestCID: randomHexBytes(),
    responseCID: randomHexBytes(),
    subgraphDeploymentID: randomHexBytes(),
  }
  let dispute: Dispute

  before(async function() {
    // Helpers
    this.advanceToNextEpoch = async () => {
      const currentBlock = await latestBlock()
      const epochLength = await epochManager.epochLength()
      const nextEpochBlock = currentBlock.add(epochLength)
      await advanceBlockTo(nextEpochBlock)
    }
  })

  beforeEach(async function() {
    // Deploy epoch contract
    epochManager = await deployment.deployEpochManager(governor.address)

    // Deploy graph token
    grt = await deployment.deployGRT(governor.address)

    // Deploy staking contract
    staking = await deployment.deployStaking(
      governor,
      grt.address,
      epochManager.address,
      AddressZero,
    )

    // Deploy dispute contract
    disputeManager = await deployment.deployDisputeManager(
      governor.address,
      grt.address,
      arbitrator.address,
      staking.address,
    )

    // Create an attestation
    const attestation = await attestations.createAttestation(
      indexerChannelPrivKey,
      (await getChainID()) as number,
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

  describe('configuration', () => {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await disputeManager.governor()).to.eq(governor.address)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await disputeManager.token()).to.eq(grt.address)
    })

    describe('arbitrator', function() {
      it('should set `arbitrator`', async function() {
        // Set right in the constructor
        expect(await disputeManager.arbitrator()).to.eq(arbitrator.address)

        // Can set if allowed
        await disputeManager.connect(governor).setArbitrator(other.address)
        expect(await disputeManager.arbitrator()).to.eq(other.address)
      })

      it('reject set `arbitrator` if not allowed', async function() {
        const tx = disputeManager.connect(other).setArbitrator(arbitrator.address)
        await expect(tx).to.revertedWith('Only Governor can call')
      })
    })

    describe('minimumDeposit', function() {
      it('should set `minimumDeposit`', async function() {
        const oldValue = defaults.dispute.minimumDeposit
        const newValue = toBN('1')

        // Set right in the constructor
        expect(await disputeManager.minimumDeposit()).to.eq(oldValue)

        // Set new value
        await disputeManager.connect(governor).setMinimumDeposit(newValue)
        expect(await disputeManager.minimumDeposit()).to.eq(newValue)
      })

      it('reject set `minimumDeposit` if not allowed', async function() {
        const newValue = toBN('1')
        const tx = disputeManager.connect(other).setMinimumDeposit(newValue)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('fishermanRewardPercentage', function() {
      it('should set `fishermanRewardPercentage`', async function() {
        const newValue = defaults.dispute.fishermanRewardPercentage

        // Set right in the constructor
        expect(await disputeManager.fishermanRewardPercentage()).to.eq(newValue)

        // Set new value
        await disputeManager.connect(governor).setFishermanRewardPercentage(0)
        await disputeManager.connect(governor).setFishermanRewardPercentage(newValue)
      })

      it('reject set `fishermanRewardPercentage` if out of bounds', async function() {
        const tx = disputeManager.connect(governor).setFishermanRewardPercentage(MAX_PPM + 1)
        await expect(tx).to.be.revertedWith('Reward percentage must be below or equal to MAX_PPM')
      })

      it('reject set `fishermanRewardPercentage` if not allowed', async function() {
        const tx = disputeManager.connect(other).setFishermanRewardPercentage(50)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('slashingPercentage', function() {
      it('should set `slashingPercentage`', async function() {
        const newValue = defaults.dispute.slashingPercentage

        // Set right in the constructor
        expect(await disputeManager.slashingPercentage()).to.eq(newValue.toString())

        // Set new value
        await disputeManager.connect(governor).setSlashingPercentage(0)
        await disputeManager.connect(governor).setSlashingPercentage(newValue)
      })

      it('reject set `slashingPercentage` if out of bounds', async function() {
        const tx = disputeManager.connect(governor).setSlashingPercentage(MAX_PPM + 1)
        await expect(tx).to.be.revertedWith('Slashing percentage must be below or equal to MAX_PPM')
      })

      it('reject set `slashingPercentage` if not allowed', async function() {
        const tx = disputeManager.connect(other).setSlashingPercentage(50)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('staking', function() {
      it('should set `staking`', async function() {
        // Set right in the constructor
        expect(await disputeManager.staking()).to.eq(staking.address)

        // Can set if allowed
        await disputeManager.connect(governor).setStaking(grt.address)
        expect(await disputeManager.staking()).to.eq(grt.address)
      })

      it('reject set `staking` if not allowed', async function() {
        const tx = disputeManager.connect(other).setStaking(grt.address)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })
  })

  describe('dispute lifecycle', function() {
    beforeEach(async function() {
      // Give some funds to the fisherman
      this.fishermanTokens = toGRT('100000')
      this.fishermanDeposit = toGRT('1000')
      await grt.connect(governor).mint(fisherman.address, this.fishermanTokens)
      await grt.connect(fisherman).approve(disputeManager.address, this.fishermanTokens)
    })

    it('reject create a dispute if attestation does not refer to valid indexer', async function() {
      // Create dispute
      const tx = disputeManager
        .connect(fisherman)
        .createDispute(dispute.encodedAttestation, this.fishermanDeposit)
      await expect(tx).to.be.revertedWith('Indexer cannot be found for the attestation')
    })

    it('reject create a dispute if indexer has no stake', async function() {
      // This tests reproduce the case when someones present a dispute after
      // an indexer removed his stake completely and find nothing to slash

      const indexerTokens = toGRT('100000')
      const indexerAllocatedTokens = toGRT('10000')
      const indexerSettledTokens = toGRT('10')

      // Give some funds to the indexer
      await grt.connect(governor).mint(indexer.address, indexerTokens)
      await grt.connect(indexer).approve(staking.address, indexerTokens)

      // Give some funds to the channel
      await grt.connect(governor).mint(channelProxy.address, indexerSettledTokens)
      await grt.connect(channelProxy).approve(staking.address, indexerSettledTokens)

      // Set the thawing period to zero to make the test easier
      await staking.connect(governor).setThawingPeriod(toBN('0'))

      // Indexer stake funds, allocate, settle, unstake and withdraw the stake fully
      await staking.connect(indexer).stake(indexerTokens)
      await staking
        .connect(indexer)
        .allocate(
          dispute.receipt.subgraphDeploymentID,
          indexerAllocatedTokens,
          indexerChannelPubKey,
          channelProxy.address,
          toBN('0'),
        )
      await this.advanceToNextEpoch() // wait the required one epoch to settle
      await staking.connect(channelProxy).settle(indexerSettledTokens)
      await staking.connect(indexer).unstake(indexerTokens)
      await staking.connect(indexer).withdraw() // no thawing period so we are good

      // Create dispute
      const tx = disputeManager
        .connect(fisherman)
        .createDispute(dispute.encodedAttestation, this.fishermanDeposit)
      await expect(tx).to.be.revertedWith('Dispute has no stake by the indexer')
    })

    context('> when indexer has staked', function() {
      beforeEach(async function() {
        // Dispute manager is allowed to slash
        await staking.connect(governor).setSlasher(disputeManager.address, true)

        // Stake
        this.indexerTokens = toGRT('100000')
        this.indexerAllocatedTokens = toGRT('10000')
        const indexerList = [
          { wallet: indexer, pubKey: indexerChannelPubKey },
          { wallet: otherIndexer, pubKey: otherIndexerChannelPubKey },
        ]
        for (const activeIndexer of indexerList) {
          const indexerWallet = activeIndexer.wallet
          const indexerPubKey = activeIndexer.pubKey

          // Give some funds to the indexer
          await grt.connect(governor).mint(indexerWallet.address, this.indexerTokens)
          await grt.connect(indexerWallet).approve(staking.address, this.indexerTokens)

          // Indexer stake funds
          await staking.connect(indexerWallet).stake(this.indexerTokens)
          await staking
            .connect(indexerWallet)
            .allocate(
              dispute.receipt.subgraphDeploymentID,
              this.indexerAllocatedTokens,
              indexerPubKey,
              channelProxy.address,
              toBN('0'),
            )
        }
      })

      describe('reward calculation', function() {
        it('should calculate the reward for a stake', async function() {
          const stakedAmount = this.indexerTokens
          const trueReward = stakedAmount
            .mul(defaults.dispute.slashingPercentage)
            .div(toBN(MAX_PPM))
            .mul(defaults.dispute.fishermanRewardPercentage)
            .div(toBN(MAX_PPM))
          const funcReward = await disputeManager.getTokensToReward(indexer.address)
          expect(funcReward).to.eq(trueReward.toString())
        })
      })

      describe('create dispute', function() {
        it('reject fisherman deposit below minimum required', async function() {
          // Minimum deposit a fisherman is required to do should be >= reward
          const minimumDeposit = await disputeManager.minimumDeposit()
          const belowMinimumDeposit = minimumDeposit.sub(toBN('1'))

          // Create invalid dispute as deposit is below minimum
          const tx = disputeManager
            .connect(fisherman)
            .createDispute(dispute.encodedAttestation, belowMinimumDeposit)
          await expect(tx).to.be.revertedWith('Dispute deposit is under minimum required')
        })

        it('should create a dispute', async function() {
          // Create dispute
          const tx = disputeManager
            .connect(fisherman)
            .createDispute(dispute.encodedAttestation, this.fishermanDeposit)
          await expect(tx)
            .to.emit(disputeManager, 'DisputeCreated')
            .withArgs(
              dispute.id,
              dispute.receipt.subgraphDeploymentID,
              dispute.indexerAddress,
              fisherman.address,
              this.fishermanDeposit,
              dispute.encodedAttestation,
            )
        })
      })

      describe('accept a dispute', function() {
        it('reject to accept a non-existing dispute', async function() {
          const tx = disputeManager.connect(arbitrator).acceptDispute(NON_EXISTING_DISPUTE_ID)
          await expect(tx).to.be.revertedWith('Dispute does not exist')
        })
      })

      describe('reject a dispute', function() {
        it('reject to reject a non-existing dispute', async function() {
          const tx = disputeManager.connect(arbitrator).rejectDispute(NON_EXISTING_DISPUTE_ID)
          await expect(tx).to.be.revertedWith('Dispute does not exist')
        })
      })

      describe('draw a dispute', function() {
        it('reject to draw a non-existing dispute', async function() {
          const tx = disputeManager.connect(arbitrator).drawDispute(NON_EXISTING_DISPUTE_ID)
          await expect(tx).to.be.revertedWith('Dispute does not exist')
        })
      })

      context('> when dispute is created', function() {
        beforeEach(async function() {
          // Create dispute
          await disputeManager
            .connect(fisherman)
            .createDispute(dispute.encodedAttestation, this.fishermanDeposit)
        })

        describe('create a dispute', function() {
          it('should create dispute if receipt is equal but for other indexer', async function() {
            // Create dispute (same receipt but different indexer)
            const attestation = await attestations.createAttestation(
              otherIndexerChannelPrivKey,
              (await getChainID()) as number,
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

            const tx = disputeManager
              .connect(fisherman)
              .createDispute(newDispute.encodedAttestation, this.fishermanDeposit)
            expect(tx)
              .to.emit(disputeManager, 'DisputeCreated')
              .withArgs(
                newDispute.id,
                newDispute.receipt.subgraphDeploymentID,
                newDispute.indexerAddress,
                fisherman.address,
                this.fishermanDeposit,
                newDispute.encodedAttestation,
              )
          })

          it('reject create duplicated dispute', async function() {
            const tx = disputeManager
              .connect(fisherman)
              .createDispute(dispute.encodedAttestation, this.fishermanDeposit)
            await expect(tx).to.be.revertedWith('Dispute already created')
          })
        })

        describe('accept a dispute', function() {
          it('reject to accept a dispute if not the arbitrator', async function() {
            const tx = disputeManager.connect(me).acceptDispute(dispute.id)
            await expect(tx).to.be.revertedWith('Caller is not the Arbitrator')
          })

          it('reject to accept a dispute if not slasher', async function() {
            // Dispute manager is not allowed to slash
            await staking.connect(governor).setSlasher(disputeManager.address, false)

            // Perform transaction (accept)
            const tx = disputeManager.connect(arbitrator).acceptDispute(dispute.id)
            await expect(tx).to.be.revertedWith('Caller is not a Slasher')
          })

          it('reject to accept a dispute if zero tokens to slash', async function() {
            await disputeManager.connect(governor).setSlashingPercentage(toBN('0'))
            const tx = disputeManager.connect(arbitrator).acceptDispute(dispute.id)
            await expect(tx).to.be.revertedWith('Dispute has zero tokens to slash')
          })

          it('should resolve dispute, slash indexer and reward the fisherman', async function() {
            const indexerStakeBefore = await staking.getIndexerStakedTokens(indexer.address)
            const tokensToSlash = await disputeManager.getTokensToSlash(indexer.address)
            const fishermanBalanceBefore = await grt.balanceOf(fisherman.address)
            const totalSupplyBefore = await grt.totalSupply()
            const reward = await disputeManager.getTokensToReward(indexer.address)

            // Perform transaction (accept)
            const tx = disputeManager.connect(arbitrator).acceptDispute(dispute.id)
            await expect(tx)
              .to.emit(disputeManager, 'DisputeAccepted')
              .withArgs(
                dispute.id,
                dispute.receipt.subgraphDeploymentID,
                dispute.indexerAddress,
                fisherman.address,
                this.fishermanDeposit.add(reward),
              )

            // Fisherman reward properly assigned + deposit returned
            const fishermanBalanceAfter = await grt.balanceOf(fisherman.address)
            expect(fishermanBalanceAfter).to.eq(
              fishermanBalanceBefore.add(this.fishermanDeposit).add(reward),
            )

            // Indexer slashed
            const indexerStakeAfter = await staking.getIndexerStakedTokens(indexer.address)
            expect(indexerStakeAfter).to.eq(indexerStakeBefore.sub(tokensToSlash))

            // Slashed funds burned
            const tokensToBurn = tokensToSlash.sub(reward)
            const totalSupplyAfter = await grt.totalSupply()
            expect(totalSupplyAfter).to.eq(totalSupplyBefore.sub(tokensToBurn))
          })
        })

        describe('reject a dispute', async function() {
          it('reject to reject a dispute if not the arbitrator', async function() {
            const tx = disputeManager.connect(me).rejectDispute(dispute.id)
            await expect(tx).to.be.revertedWith('Caller is not the Arbitrator')
          })

          it('should reject a dispute and burn deposit', async function() {
            const fishermanBalanceBefore = await grt.balanceOf(fisherman.address)
            const totalSupplyBefore = await grt.totalSupply()

            // Perform transaction (reject)
            const tx = disputeManager.connect(arbitrator).rejectDispute(dispute.id)
            await expect(tx)
              .to.emit(disputeManager, 'DisputeRejected')
              .withArgs(
                dispute.id,
                dispute.receipt.subgraphDeploymentID,
                dispute.indexerAddress,
                fisherman.address,
                this.fishermanDeposit,
              )

            // No change in fisherman balance
            const fishermanBalanceAfter = await grt.balanceOf(fisherman.address)
            expect(fishermanBalanceAfter).to.eq(fishermanBalanceBefore)

            // Burn fisherman deposit
            const totalSupplyAfter = await grt.totalSupply()
            const burnedTokens = toBN(this.fishermanDeposit)
            expect(totalSupplyAfter).to.eq(totalSupplyBefore.sub(burnedTokens))
          })
        })

        describe('draw a dispute', async function() {
          it('reject to draw a dispute if not the arbitrator', async function() {
            const tx = disputeManager.connect(me).drawDispute(dispute.id)
            await expect(tx).to.be.revertedWith('Caller is not the Arbitrator')
          })

          it('should draw a dispute and return deposit', async function() {
            const fishermanBalanceBefore = await grt.balanceOf(fisherman.address)

            // Perform transaction (draw)
            const tx = disputeManager.connect(arbitrator).drawDispute(dispute.id)
            await expect(tx)
              .to.emit(disputeManager, 'DisputeDrawn')
              .withArgs(
                dispute.id,
                dispute.receipt.subgraphDeploymentID,
                dispute.indexerAddress,
                fisherman.address,
                this.fishermanDeposit,
              )

            // Fisherman should see the deposit returned
            const fishermanBalanceAfter = await grt.balanceOf(fisherman.address)
            expect(fishermanBalanceAfter).to.eq(fishermanBalanceBefore.add(this.fishermanDeposit))
          })
        })
      })
    })
  })
})

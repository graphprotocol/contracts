import { expect } from 'chai'
import { Wallet } from 'ethers'
import { BigNumber } from 'ethers/utils'
import { AddressZero } from 'ethers/constants'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import * as deployment from '../lib/deployment'
import {
  advanceBlockTo,
  defaults,
  getChainID,
  randomHexBytes,
  latestBlock,
  provider,
  toBN,
  toGRT,
} from '../lib/testHelpers'

const MAX_PPM = toBN('1000000')

function weightedAverage(
  valueA: BigNumber,
  valueB: BigNumber,
  periodA: BigNumber,
  periodB: BigNumber,
) {
  return periodA
    .mul(valueA)
    .add(periodB.mul(valueB))
    .div(valueA.add(valueB))
}

describe('Staking', () => {
  const [me, other, governor, indexer, slasher, fisherman, channelProxy] = provider().getWallets()

  let curation: Curation
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

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
    epochManager = await deployment.deployEpochManager(governor.address, me)

    // Deploy graph token
    grt = await deployment.deployGRT(governor.address, me)

    // Deploy curation contract
    curation = await deployment.deployCuration(governor.address, grt.address, me)

    // Deploy staking contract
    staking = await deployment.deployStaking(
      governor,
      grt.address,
      epochManager.address,
      curation.address,
      me,
    )

    // Set slasher
    await staking.connect(governor).setSlasher(slasher.address, true)

    // Set staking as distributor of funds to curation
    await curation.connect(governor).setStaking(staking.address)
  })

  describe('configuration', function() {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await staking.governor()).to.eq(governor.address)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await staking.token()).to.eq(grt.address)
    })

    describe('setSlasher', function() {
      it('should set `slasher`', async function() {
        expect(await staking.slashers(me.address)).to.be.eq(false)
        await staking.connect(governor).setSlasher(me.address, true)
        expect(await staking.slashers(me.address)).to.be.eq(true)
      })

      it('reject set `slasher` if not allowed', async function() {
        const tx = staking.connect(other).setSlasher(me.address, true)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('channelDisputeEpochs', function() {
      it('should set `channelDisputeEpochs`', async function() {
        const newValue = toBN('5')
        await staking.connect(governor).setChannelDisputeEpochs(newValue)
        expect(await staking.channelDisputeEpochs()).to.eq(newValue)
      })

      it('reject set `channelDisputeEpochs` if not allowed', async function() {
        const newValue = toBN('5')
        const tx = staking.connect(other).setChannelDisputeEpochs(newValue)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('curation', function() {
      it('should set `curation`', async function() {
        // Set right in the constructor
        expect(await staking.curation()).to.eq(curation.address)

        await staking.connect(governor).setCuration(AddressZero)
        expect(await staking.curation()).to.eq(AddressZero)
      })

      it('reject set `curation` if not allowed', async function() {
        const tx = staking.connect(other).setChannelDisputeEpochs(AddressZero)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('curationPercentage', function() {
      it('should set `curationPercentage`', async function() {
        const newValue = toBN('5')
        await staking.connect(governor).setCurationPercentage(newValue)
        expect(await staking.curationPercentage()).to.eq(newValue)
      })

      it('reject set `curationPercentage` if out of bounds', async function() {
        const newValue = MAX_PPM.add(toBN('1'))
        const tx = staking.connect(governor).setCurationPercentage(newValue)
        await expect(tx).to.be.revertedWith('Curation percentage must be below or equal to MAX_PPM')
      })

      it('reject set `curationPercentage` if not allowed', async function() {
        const tx = staking.connect(other).setCurationPercentage(50)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('maxAllocationEpochs', function() {
      it('should set `maxAllocationEpochs`', async function() {
        const newValue = toBN('5')
        await staking.connect(governor).setMaxAllocationEpochs(newValue)
        expect(await staking.maxAllocationEpochs()).to.eq(newValue)
      })

      it('reject set `maxAllocationEpochs` if not allowed', async function() {
        const newValue = toBN('5')
        const tx = staking.connect(other).setMaxAllocationEpochs(newValue)
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('thawingPeriod', function() {
      it('should set `thawingPeriod`', async function() {
        const newValue = toBN('5')
        await staking.connect(governor).setThawingPeriod(newValue)
        expect(await staking.thawingPeriod()).to.eq(newValue)
      })

      it('reject set `thawingPeriod` if not allowed', async function() {
        const newValue = toBN('5')
        const tx = staking.connect(other).setThawingPeriod(newValue)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })
  })

  describe('staking', function() {
    before(async function() {
      // Helpers
      this.stake = async function(tokens: BigNumber) {
        return staking.connect(indexer).stake(tokens)
      }
      this.allocate = function(tokens: BigNumber) {
        return staking
          .connect(indexer)
          .allocate(
            this.subgraphDeploymentID,
            tokens,
            this.channelPubKey,
            channelProxy.address,
            this.price,
          )
      }
      this.shouldStake = async function(indexerStake: BigNumber) {
        // Setup
        const indexerStakeBefore = await staking.getIndexerStakedTokens(indexer.address)

        // Stake
        const tx = this.stake(indexerStake)
        await expect(tx)
          .to.emit(staking, 'StakeDeposited')
          .withArgs(indexer.address, indexerStake)

        // State updated
        const indexerStakeAfter = await staking.getIndexerStakedTokens(indexer.address)
        expect(indexerStakeAfter).to.eq(indexerStakeBefore.add(indexerStake))
      }
    })

    beforeEach(async function() {
      // Setup
      this.indexerStake = toGRT('100')
      this.subgraphDeploymentID = randomHexBytes()
      this.channelID = '0x6367E9dD7641e0fF221740b57B8C730031d72530'
      this.channelPubKey =
        '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'
      this.price = toGRT('0.01')

      // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
      this.indexerTokens = toGRT('1000')
      await grt.connect(governor).mint(indexer.address, this.indexerTokens)
      await grt.connect(indexer).approve(staking.address, this.indexerTokens)
    })

    describe('hasStake()', function() {
      it('should not have stakes', async function() {
        expect(await staking.hasStake(indexer.address)).to.be.eq(false)
      })
    })

    describe('stake()', function() {
      it('should stake tokens', async function() {
        await this.shouldStake(this.indexerStake)
      })

      it('reject stake zero tokens', async function() {
        const tx = this.stake(toBN('0'))
        await expect(tx).to.be.revertedWith('Staking: cannot stake zero tokens')
      })
    })

    describe('unstake()', function() {
      it('reject unstake tokens', async function() {
        const tokensToUnstake = toGRT('2')
        const tx = staking.connect(indexer).unstake(tokensToUnstake)
        await expect(tx).to.be.revertedWith('Staking: indexer has no stakes')
      })
    })

    describe('allocate()', function() {
      it('reject allocate', async function() {
        const indexerStake = toGRT('100')
        const tx = this.allocate(indexerStake)
        await expect(tx).to.be.revertedWith('Allocation: indexer has no stakes')
      })
    })

    describe('slash()', function() {
      it('reject slash indexer', async function() {
        const tokensToSlash = toGRT('10')
        const tokensToReward = toGRT('10')
        const tx = staking
          .connect(slasher)
          .slash(indexer.address, tokensToSlash, tokensToReward, fisherman.address)
        await expect(tx).to.be.revertedWith('Slashing: indexer has no stakes')
      })
    })

    context('> when staked', function() {
      beforeEach(async function() {
        // Stake
        await this.stake(this.indexerStake)
      })

      describe('hasStake()', function() {
        it('should have stakes', async function() {
          expect(await staking.hasStake(indexer.address)).to.be.eq(true)
        })
      })

      describe('stake()', function() {
        it('should allow re-staking', async function() {
          await this.shouldStake(this.indexerStake)
        })
      })

      describe('unstake()', function() {
        it('should unstake and lock tokens for thawing period', async function() {
          const tokensToUnstake = toGRT('2')
          const thawingPeriod = await staking.thawingPeriod()
          const currentBlock = await latestBlock()
          const until = currentBlock.add(thawingPeriod).add(toBN('1'))

          // Unstake
          const tx = staking.connect(indexer).unstake(tokensToUnstake)
          await expect(tx)
            .to.emit(staking, 'StakeLocked')
            .withArgs(indexer.address, tokensToUnstake, until)
        })

        // it('should unstake and lock tokens for (weighted avg) thawing period if repeated', async function() {
        //   const tokensToUnstake = toGRT('10')
        //   const thawingPeriod = await staking.thawingPeriod()

        //   // Unstake (1)
        //   const tx1 = await staking.connect(indexer).unstake(tokensToUnstake)
        //   const r1 = await provider().getTransactionReceipt(tx1.hash)
        //   console.log(r1)
        //   const tokensLockedUntil1 = r1.logs[0].args.until

        //   // Move forward
        //   await advanceBlockTo(tokensLockedUntil1)

        //   // Calculate locking time for tokens taking into account the previous unstake request
        //   const currentBlock = await latestBlock()
        //   const lockingPeriod = weightedAverage(
        //     tokensToUnstake,
        //     tokensToUnstake,
        //     tokensLockedUntil1.sub(currentBlock),
        //     thawingPeriod,
        //   )
        //   const expectedLockedUntil = currentBlock.add(lockingPeriod).add(toBN('1'))

        //   // Unstake (2)
        //   r = await staking.connect(indexer).unstake(tokensToUnstake)
        //   const tokensLockedUntil2 = r.logs[0].args.until
        //   expect(expectedLockedUntil).to.eq(tokensLockedUntil2)
        // })

        it('reject unstake more than available tokens', async function() {
          const tokensOverCapacity = this.indexerStake.add(toBN('1'))
          const tx = staking.connect(indexer).unstake(tokensOverCapacity)
          await expect(tx).to.be.revertedWith('Staking: not enough tokens available to unstake')
        })
      })

      describe('withdraw()', function() {
        // it('should withdraw if tokens available', async function() {
        //   // Unstake
        //   const tokensToUnstake = toGRT('10')
        //   const tx1 = await staking.connect(indexer).unstake(tokensToUnstake)
        //   const tokensLockedUntil = logs[0].args.until

        //   // Withdraw on locking period (should fail)
        //   const tx = staking.connect(indexer).withdraw()
        //   await expect(tx).to.be.revertedWith('Staking: no tokens available to withdraw')

        //   // Move forward
        //   await advanceBlockTo(tokensLockedUntil)

        //   // Withdraw after locking period (all good)
        //   const balanceBefore = await grt.balanceOf(indexer.address)
        //   await staking.connect(indexer).withdraw()
        //   const balanceAfter = await grt.balanceOf(indexer.address)
        //   expect(balanceAfter).to.eq(balanceBefore.add(tokensToUnstake))
        // })

        it('reject withdraw if no tokens available', async function() {
          const tx = staking.connect(indexer).withdraw()
          await expect(tx).to.be.revertedWith('Staking: no tokens available to withdraw')
        })
      })

      describe('slash()', function() {
        before(function() {
          // Helpers

          // This function tests slashing behaviour under different conditions
          this.shouldSlash = async function(
            indexer: Wallet,
            tokensToSlash: BigNumber,
            tokensToReward: BigNumber,
            fisherman: Wallet,
          ) {
            // Before
            const beforeTotalSupply = await grt.totalSupply()
            const beforeFishermanTokens = await grt.balanceOf(fisherman.address)
            const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

            // Slash indexer
            const tokensToBurn = tokensToSlash.sub(tokensToReward)
            const tx = staking
              .connect(slasher)
              .slash(indexer.address, tokensToSlash, tokensToReward, fisherman.address)
            await expect(tx)
              .to.emit(staking, 'StakeSlashed')
              .withArgs(indexer.address, tokensToSlash, tokensToReward, fisherman.address)

            // After
            const afterTotalSupply = await grt.totalSupply()
            const afterFishermanTokens = await grt.balanceOf(fisherman.address)
            const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

            // Check slashed tokens has been burned
            expect(afterTotalSupply).to.eq(beforeTotalSupply.sub(tokensToBurn))
            // Check reward was given to the fisherman
            expect(afterFishermanTokens).to.eq(beforeFishermanTokens.add(tokensToReward))
            // Check indexer stake was updated
            expect(afterIndexerStake).to.eq(beforeIndexerStake.sub(tokensToSlash))
          }
        })

        it('should slash indexer and give reward to beneficiary slash>reward', async function() {
          // Slash indexer
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('10')
          await this.shouldSlash(indexer, tokensToSlash, tokensToReward, fisherman)
        })

        it('should slash indexer and give reward to beneficiary slash=reward', async function() {
          // Slash indexer
          const tokensToSlash = toGRT('10')
          const tokensToReward = toGRT('10')
          await this.shouldSlash(indexer, tokensToSlash, tokensToReward, fisherman)
        })

        it('should slash indexer even when overallocated', async function() {
          // Initial stake
          const beforeTokensStaked = await staking.getIndexerStakedTokens(indexer.address)

          // Unstake partially, these tokens will be locked
          const tokensToUnstake = toGRT('10')
          await staking.connect(indexer).unstake(tokensToUnstake)

          // Allocate indexer stake
          const tokensToAllocate = toGRT('70')
          await this.allocate(tokensToAllocate)

          // State pre-slashing
          // helpers.logStake(await staking.stakes(indexer))
          // > Current state:
          // = Staked: 100
          // = Locked: 10
          // = Allocated: 70
          // = Available: 20 (staked - allocated - locked)

          // Even if all stake is allocated it should slash the indexer
          const tokensToSlash = toGRT('80')
          const tokensToReward = toGRT('0')
          await this.shouldSlash(indexer, tokensToSlash, tokensToReward, fisherman)

          // State post-slashing
          // helpers.logStake(await staking.stakes(indexer))
          // > Current state:
          // = Staked: 20
          // = Locked: 0
          // = Allocated: 70
          // = Available: -50 (staked - allocated - locked) => when tokens available becomes negative
          // we are overallocated, the staking contract will prevent unstaking or allocating until
          // the balance is restored by staking or unallocating

          const stakes = await staking.stakes(indexer.address)
          // Stake should be reduced by the amount slashed
          expect(stakes.tokensIndexer).to.eq(beforeTokensStaked.sub(tokensToSlash))
          // All allocated tokens should be untouched
          expect(stakes.tokensAllocated).to.eq(tokensToAllocate)
          // All locked tokens need to be consumed from the stake
          expect(stakes.tokensLocked).to.eq(toBN('0'))
          expect(stakes.tokensLockedUntil).to.eq(toBN('0'))
          // Tokens available when negative means over allocation
          const tokensAvailable = stakes.tokensIndexer
            .sub(stakes.tokensAllocated)
            .sub(stakes.tokensLocked)
          expect(tokensAvailable).to.eq(toGRT('-50'))

          const tx = staking.connect(indexer).unstake(tokensToUnstake)
          await expect(tx).to.be.revertedWith('Staking: not enough tokens available to unstake')
        })

        it('reject to slash zero tokens', async function() {
          const tokensToSlash = toGRT('0')
          const tokensToReward = toGRT('0')
          const tx = staking
            .connect(slasher)
            .slash(indexer.address, tokensToSlash, tokensToReward, me.address)
          await expect(tx).to.be.revertedWith('Slashing: cannot slash zero tokens')
        })

        it('reject to slash indexer if caller is not slasher', async function() {
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('10')
          const tx = staking
            .connect(me)
            .slash(indexer.address, tokensToSlash, tokensToReward, me.address)
          await expect(tx).to.be.revertedWith('Caller is not a Slasher')
        })

        it('reject to slash indexer if beneficiary is zero address', async function() {
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('10')
          const tx = staking
            .connect(slasher)
            .slash(indexer.address, tokensToSlash, tokensToReward, AddressZero)
          await expect(tx).to.be.revertedWith('Slashing: beneficiary must not be an empty address')
        })

        it('reject to slash indexer if reward is greater than slash amount', async function() {
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('200')
          const tx = staking
            .connect(slasher)
            .slash(indexer.address, tokensToSlash, tokensToReward, fisherman.address)
          await expect(tx).to.be.revertedWith(
            'Slashing: reward cannot be higher than slashed amoun',
          )
        })
      })

      describe('allocate()', function() {
        it('should allocate', async function() {
          const tx = this.allocate(this.indexerStake)
          await expect(tx)
            .to.emit(staking, 'AllocationCreated')
            .withArgs(
              indexer.address,
              this.subgraphDeploymentID,
              await epochManager.currentEpoch(),
              this.indexerStake,
              this.channelID,
              this.channelPubKey,
              this.price,
            )
        })

        it('reject allocate more than available tokens', async function() {
          const tokensOverCapacity = this.indexerStake.add(toBN('1'))
          const tx = this.allocate(tokensOverCapacity)
          await expect(tx).to.be.revertedWith('Allocation: not enough tokens available to allocate')
        })

        it('reject allocate zero tokens', async function() {
          const zeroTokens = toGRT('0')
          const tx = this.allocate(zeroTokens)
          await expect(tx).to.be.revertedWith('Allocation: cannot allocate zero tokens')
        })

        context('> when allocated', function() {
          beforeEach(async function() {
            this.tokensAllocated = toGRT('10')
            await this.allocate(this.tokensAllocated)
          })

          it('reject allocate again if not settled', async function() {
            const tokensToAllocate = toGRT('10')
            const tx = this.allocate(tokensToAllocate)
            await expect(tx).to.be.revertedWith('Allocation: cannot allocate if already allocated')
          })

          it('reject allocate reusing a channel', async function() {
            const tokensToAllocate = toGRT('10')
            const subgraphDeploymentID = randomHexBytes()
            const tx = staking
              .connect(indexer)
              .allocate(
                subgraphDeploymentID,
                tokensToAllocate,
                this.channelPubKey,
                channelProxy.address,
                this.price,
              )
            await expect(tx).to.be.revertedWith('Allocation: channel ID already in use')
          })
        })
      })

      describe('settle()', function() {
        beforeEach(async function() {
          this.tokensAllocated = toGRT('10')
          this.tokensToSettle = toGRT('100')

          // Create the allocation to be settled
          await this.allocate(this.tokensAllocated)
          await grt.connect(governor).mint(channelProxy.address, this.tokensToSettle)
          await grt.connect(channelProxy).approve(staking.address, this.tokensToSettle)
        })

        it('should settle and distribute funds', async function() {
          const stakeBefore = await staking.stakes(indexer.address)
          const allocBefore = await staking.getAllocation(
            indexer.address,
            this.subgraphDeploymentID,
          )

          // Curate the subgraph to be settled to get curation fees distributed
          const tokensToSignal = toGRT('100')
          await grt.connect(governor).mint(me.address, tokensToSignal)
          await grt.connect(me).approve(curation.address, tokensToSignal)
          await curation.connect(me).stake(this.subgraphDeploymentID, tokensToSignal)

          // Curation parameters
          const curationPercentage = toBN('200000') // 20%
          await staking.connect(governor).setCurationPercentage(curationPercentage)

          // Advance blocks to get the channel in epoch where it can be settled
          await this.advanceToNextEpoch()

          // Get epoch information
          const result = await epochManager.epochsSince(allocBefore.createdAtEpoch)
          const epochs = result[0].add(toBN('1'))
          const settlementEpoch = result[1].add(toBN('1'))

          // Calculat expected results
          const curationFees = this.tokensToSettle.mul(curationPercentage).div(MAX_PPM)
          const rebateFees = this.tokensToSettle.sub(curationFees) // calculate expected fees
          const effectiveAlloc = this.tokensAllocated.mul(epochs) // effective allocation

          // Settle
          const tx = staking.connect(channelProxy).settle(this.tokensToSettle)
          await expect(tx)
            .to.emit(staking, 'AllocationSettled')
            .withArgs(
              indexer.address,
              this.subgraphDeploymentID,
              settlementEpoch,
              this.tokensToSettle,
              this.channelID,
              channelProxy.address,
              curationFees,
              rebateFees,
              effectiveAlloc,
            )

          // Check that curation reserves increased for that SubgraphDeployment
          const subgraphAfter = await curation.subgraphDeployments(this.subgraphDeploymentID)
          expect(subgraphAfter.tokens).to.eq(tokensToSignal.add(curationFees))

          // Verify stake is updated
          const stakeAfter = await staking.stakes(indexer.address)
          expect(stakeAfter.tokensAllocated).to.eq(
            stakeBefore.tokensAllocated.sub(allocBefore.tokens),
          )

          // Verify allocation is updated and channel closed
          const allocAfter = await staking.getAllocation(indexer.address, this.subgraphDeploymentID)
          expect(allocAfter.tokens).to.eq(toBN('0'))
          expect(allocAfter.createdAtEpoch).to.eq(toBN('0'))
          expect(allocAfter.channelID).to.be.eq(AddressZero)

          // Verify rebate information is stored
          const settlement = await staking.getSettlement(
            settlementEpoch,
            indexer.address,
            this.subgraphDeploymentID,
          )
          expect(settlement.fees).to.eq(rebateFees)
          expect(settlement.allocation).to.eq(effectiveAlloc)
        })

        it('should settle zero tokens', async function() {
          // Advance blocks to get the channel in epoch where it can be settled
          await this.advanceToNextEpoch()

          // Settle zero tokens
          await staking.connect(channelProxy).settle(toBN('0'))
        })

        it('reject settle if channel does not exist', async function() {
          const tx = staking.connect(other).settle(this.tokensToSettle)
          await expect(tx).to.be.revertedWith('Channel: does not exist')
        })

        it('reject settle from an already settled channel', async function() {
          // Advance blocks to get the channel in epoch where it can be settled
          await this.advanceToNextEpoch()

          // Settle the channel
          await staking.connect(channelProxy).settle(this.tokensToSettle.div(toBN('2')))

          // Settle the same channel to force an error
          const tx = staking.connect(channelProxy).settle(this.tokensToSettle.div(toBN('2')))
          await expect(tx).to.revertedWith('Channel: does not exist')
        })

        it('reject settle if an epoch has not passed', async function() {
          const tx = staking.connect(channelProxy).settle(this.tokensToSettle)
          await expect(tx).to.be.revertedWith('Channel: Can only settle after one epoch passed')
        })
      })

      describe('claim()', function() {
        before(async function() {
          // Claim and perform checks
          this.shouldClaim = async function(restake: boolean) {
            const rebatePoolBefore = await staking.rebates(this.rebateEpoch)

            // Claim rebates
            const currentEpoch = await epochManager.currentEpoch()
            const tx = staking
              .connect(indexer)
              .claim(this.rebateEpoch, this.subgraphDeploymentID, restake)
            await expect(tx)
              .to.emit(staking, 'RebateClaimed')
              .withArgs(
                indexer.address,
                this.subgraphDeploymentID,
                currentEpoch,
                this.rebateEpoch,
                this.tokensToSettle,
                rebatePoolBefore.settlementsCount.sub(toBN('1')),
              )

            // Verify the settlement is consumed when claimed and rebate pool updated
            const rebatePoolAfter = await staking.rebates(this.rebateEpoch)
            expect(rebatePoolAfter.settlementsCount).to.eq(
              rebatePoolBefore.settlementsCount.sub(toBN('1')),
            )
            if (rebatePoolAfter.settlementsCount.eq(toBN('0'))) {
              // Rebate pool is empty and then pruned
              expect(rebatePoolAfter.allocation).to.eq(toBN('0'))
              expect(rebatePoolAfter.fees).to.eq(toBN('0'))
            } else {
              // There are still more settlements in the rebate
              expect(rebatePoolAfter.allocation).to.eq(rebatePoolBefore.allocation)
              expect(rebatePoolAfter.fees).to.eq(rebatePoolBefore.fees.sub(this.tokensToSettle))
            }
          }
        })

        beforeEach(async function() {
          this.tokensAllocated = toGRT('10')
          this.tokensToSettle = toGRT('100')

          // Create the allocation to be settled
          await this.allocate(this.tokensAllocated)
          await grt.connect(governor).mint(channelProxy.address, this.tokensToSettle)
          await grt.connect(channelProxy).approve(staking.address, this.tokensToSettle)

          // Advance blocks to get the channel in epoch where it can be settled
          await this.advanceToNextEpoch()
        })

        it('reject claim if channelDisputeEpoch has not passed', async function() {
          const currentEpoch = await epochManager.currentEpoch()
          const tx = staking.connect(indexer).claim(currentEpoch, this.subgraphDeploymentID, false)
          await expect(tx).to.be.revertedWith('Rebate: need to wait channel dispute period')
        })

        it('reject claim when no settlement available for that epoch', async function() {
          const currentEpoch = await epochManager.currentEpoch()
          const subgraphDeploymentID = randomHexBytes()

          // Advance blocks to get the channel in epoch where it can be claimed
          await this.advanceToNextEpoch()

          const tx = staking.connect(indexer).claim(currentEpoch, subgraphDeploymentID, false)
          await expect(tx).to.be.revertedWith('Rebate: settlement does not exist')
        })

        it('should claim rebate of zero tokens', async function() {
          // Setup
          const indexerStakeBefore = await staking.getIndexerStakedTokens(indexer.address)
          const indexerTokensBefore = await grt.balanceOf(indexer.address)

          // Settle zero tokens
          this.tokensToSettle = toBN('0')
          await staking.connect(channelProxy).settle(this.tokensToSettle)
          this.rebateEpoch = await epochManager.currentEpoch()

          // Advance blocks to get the channel in epoch where it can be claimed
          await this.advanceToNextEpoch()

          // Claim with no restake
          await this.shouldClaim(false)

          // Verify that both stake and transferred tokens did not change
          const indexerStakeAfter = await staking.getIndexerStakedTokens(indexer.address)
          const indexerTokensAfter = await grt.balanceOf(indexer.address)
          expect(indexerStakeAfter).to.eq(indexerStakeBefore)
          expect(indexerTokensAfter).to.eq(indexerTokensBefore)
        })

        context('> when settled', function() {
          beforeEach(async function() {
            // Settle
            await staking.connect(channelProxy).settle(this.tokensToSettle)
            this.rebateEpoch = await epochManager.currentEpoch()

            // Advance blocks to get the channel in epoch where it can be claimed
            await this.advanceToNextEpoch()
          })

          it('should claim rebate', async function() {
            const indexerTokensBefore = await grt.balanceOf(indexer.address)

            // Claim with no restake
            await this.shouldClaim(false)

            // Verify that the claimed tokens are transferred to the indexer
            const indexerTokensAfter = await grt.balanceOf(indexer.address)
            expect(indexerTokensAfter).to.eq(indexerTokensBefore.add(this.tokensToSettle))
          })

          it('should claim rebate with restake', async function() {
            const indexerStakeBefore = await staking.getIndexerStakedTokens(indexer.address)

            // Claim with restake
            await this.shouldClaim(true)

            // Verify that the claimed tokens are restaked
            const indexerStakeAfter = await staking.getIndexerStakedTokens(indexer.address)
            expect(indexerStakeAfter).to.eq(indexerStakeBefore.add(this.tokensToSettle))
          })
        })
      })
    })
  })
})

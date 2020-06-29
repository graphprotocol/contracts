import { expect, use } from 'chai'
import { constants, utils, BigNumber, Event, Wallet } from 'ethers'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { loadFixture } from './fixture.test'

import {
  advanceBlockTo,
  advanceToNextEpoch,
  randomHexBytes,
  latestBlock,
  provider,
  toBN,
  toGRT,
} from '../lib/testHelpers'

use(solidity)

const { AddressZero } = constants
const { computePublicKey } = utils

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

  // Test values
  const tokensAllocated = toGRT('10')
  const tokensToCollect = toGRT('100')

  beforeEach(async function() {
    ;({ curation, epochManager, grt, staking } = await loadFixture(governor, slasher))
  })

  describe('staking', function() {
    // Setup
    const indexerTokens = toGRT('1000')
    const indexerStake = toGRT('100')
    const subgraphDeploymentID = randomHexBytes()
    const channelID = '0x6367E9dD7641e0fF221740b57B8C730031d72530'
    const channelPubKey =
      '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'
    const price = toGRT('0.01')

    // Helpers
    const stake = async function(tokens: BigNumber) {
      return staking.connect(indexer).stake(tokens)
    }
    const allocate = function(tokens: BigNumber) {
      return staking
        .connect(indexer)
        .allocate(subgraphDeploymentID, tokens, channelPubKey, channelProxy.address, price)
    }
    const shouldStake = async function(tokens: BigNumber) {
      // Before state
      const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
      const beforeStakingBalance = await grt.balanceOf(staking.address)

      // Stake
      const tx = stake(tokens)
      await expect(tx)
        .emit(staking, 'StakeDeposited')
        .withArgs(indexer.address, tokens)

      // After state
      const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
      const afterStakingBalance = await grt.balanceOf(staking.address)

      // State updated
      expect(afterIndexerStake).eq(beforeIndexerStake.add(tokens))
      expect(afterStakingBalance).eq(beforeStakingBalance.add(tokens))
    }

    beforeEach(async function() {
      // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
      await grt.connect(governor).mint(indexer.address, indexerTokens)
      await grt.connect(indexer).approve(staking.address, indexerTokens)
    })

    describe('hasStake', function() {
      it('should not have stakes', async function() {
        expect(await staking.hasStake(indexer.address)).eq(false)
      })
    })

    describe('staking', function() {
      it('should stake tokens', async function() {
        await shouldStake(indexerStake)
      })

      it('reject stake zero tokens', async function() {
        const tx = stake(toBN('0'))
        await expect(tx).revertedWith('Staking: cannot stake zero tokens')
      })
    })

    describe('unstake', function() {
      it('reject unstake tokens', async function() {
        const tokensToUnstake = toGRT('2')
        const tx = staking.connect(indexer).unstake(tokensToUnstake)
        await expect(tx).revertedWith('Staking: indexer has no stakes')
      })
    })

    describe('allocate', function() {
      it('reject allocate', async function() {
        const indexerStake = toGRT('100')
        const tx = allocate(indexerStake)
        await expect(tx).revertedWith('Allocation: indexer has no stakes')
      })
    })

    describe('slash', function() {
      it('reject slash indexer', async function() {
        const tokensToSlash = toGRT('10')
        const tokensToReward = toGRT('10')
        const tx = staking
          .connect(slasher)
          .slash(indexer.address, tokensToSlash, tokensToReward, fisherman.address)
        await expect(tx).revertedWith('Slashing: indexer has no stakes')
      })
    })

    context('> when staked', function() {
      beforeEach(async function() {
        await stake(indexerStake)
      })

      describe('hasStake', function() {
        it('should have stakes', async function() {
          expect(await staking.hasStake(indexer.address)).eq(true)
        })
      })

      describe('stake', function() {
        it('should allow re-staking', async function() {
          await shouldStake(indexerStake)
        })
      })

      describe('unstake', function() {
        it('should unstake and lock tokens for thawing period', async function() {
          const tokensToUnstake = toGRT('2')
          const thawingPeriod = await staking.thawingPeriod()
          const currentBlock = await latestBlock()
          const until = currentBlock.add(thawingPeriod).add(toBN('1'))

          // Unstake
          const tx = staking.connect(indexer).unstake(tokensToUnstake)
          await expect(tx)
            .emit(staking, 'StakeLocked')
            .withArgs(indexer.address, tokensToUnstake, until)
        })

        it('should unstake and lock tokens for (weighted avg) thawing period if repeated', async function() {
          const tokensToUnstake = toGRT('10')
          const thawingPeriod = await staking.thawingPeriod()

          // Unstake (1)
          const tx1 = await staking.connect(indexer).unstake(tokensToUnstake)
          const receipt1 = await tx1.wait()
          const event1: Event = receipt1.events.pop()
          const tokensLockedUntil1 = event1.args[2]

          // Move forward
          await advanceBlockTo(tokensLockedUntil1)

          // Calculate locking time for tokens taking into account the previous unstake request
          const currentBlock = await latestBlock()
          const lockingPeriod = weightedAverage(
            tokensToUnstake,
            tokensToUnstake,
            tokensLockedUntil1.sub(currentBlock),
            thawingPeriod,
          )
          const expectedLockedUntil = currentBlock.add(lockingPeriod).add(toBN('1'))

          // Unstake (2)
          const tx2 = await staking.connect(indexer).unstake(tokensToUnstake)
          const receipt2 = await tx2.wait()
          const event2: Event = receipt2.events.pop()
          const tokensLockedUntil2 = event2.args[2]
          expect(expectedLockedUntil).eq(tokensLockedUntil2)
        })

        it('reject unstake more than available tokens', async function() {
          const tokensOverCapacity = indexerStake.add(toBN('1'))
          const tx = staking.connect(indexer).unstake(tokensOverCapacity)
          await expect(tx).revertedWith('Staking: not enough tokens available to unstake')
        })
      })

      describe('withdraw', function() {
        it('should withdraw if tokens available', async function() {
          // Unstake
          const tokensToUnstake = toGRT('10')
          const tx1 = await staking.connect(indexer).unstake(tokensToUnstake)
          const receipt1 = await tx1.wait()
          const event1: Event = receipt1.events.pop()
          const tokensLockedUntil = event1.args[2]

          // Withdraw on locking period (should fail)
          const tx2 = staking.connect(indexer).withdraw()
          await expect(tx2).revertedWith('Staking: no tokens available to withdraw')

          // Move forward
          await advanceBlockTo(tokensLockedUntil)

          // Withdraw after locking period (all good)
          const beforeBalance = await grt.balanceOf(indexer.address)
          const tx3 = await staking.connect(indexer).withdraw()
          await expect(tx3)
            .emit(staking, 'StakeWithdrawn')
            .withArgs(indexer.address, tokensToUnstake)
          const afterBalance = await grt.balanceOf(indexer.address)
          expect(afterBalance).eq(beforeBalance.add(tokensToUnstake))
        })

        it('reject withdraw if no tokens available', async function() {
          const tx = staking.connect(indexer).withdraw()
          await expect(tx).revertedWith('Staking: no tokens available to withdraw')
        })
      })

      describe('slash', function() {
        // This function tests slashing behaviour under different conditions
        const shouldSlash = async function(
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
            .emit(staking, 'StakeSlashed')
            .withArgs(indexer.address, tokensToSlash, tokensToReward, fisherman.address)

          // After
          const afterTotalSupply = await grt.totalSupply()
          const afterFishermanTokens = await grt.balanceOf(fisherman.address)
          const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

          // Check slashed tokens has been burned
          expect(afterTotalSupply).eq(beforeTotalSupply.sub(tokensToBurn))
          // Check reward was given to the fisherman
          expect(afterFishermanTokens).eq(beforeFishermanTokens.add(tokensToReward))
          // Check indexer stake was updated
          expect(afterIndexerStake).eq(beforeIndexerStake.sub(tokensToSlash))
        }

        it('should slash indexer and give reward to beneficiary slash>reward', async function() {
          // Slash indexer
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('10')
          await shouldSlash(indexer, tokensToSlash, tokensToReward, fisherman)
        })

        it('should slash indexer and give reward to beneficiary slash=reward', async function() {
          // Slash indexer
          const tokensToSlash = toGRT('10')
          const tokensToReward = toGRT('10')
          await shouldSlash(indexer, tokensToSlash, tokensToReward, fisherman)
        })

        it('should slash indexer even when overallocated', async function() {
          // Initial stake
          const beforeTokensStaked = await staking.getIndexerStakedTokens(indexer.address)

          // Unstake partially, these tokens will be locked
          const tokensToUnstake = toGRT('10')
          await staking.connect(indexer).unstake(tokensToUnstake)

          // Allocate indexer stake
          const tokensToAllocate = toGRT('70')
          await allocate(tokensToAllocate)

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
          await shouldSlash(indexer, tokensToSlash, tokensToReward, fisherman)

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
          expect(stakes.tokensStaked).eq(beforeTokensStaked.sub(tokensToSlash))
          // All allocated tokens should be untouched
          expect(stakes.tokensAllocated).eq(tokensToAllocate)
          // All locked tokens need to be consumed from the stake
          expect(stakes.tokensLocked).eq(toBN('0'))
          expect(stakes.tokensLockedUntil).eq(toBN('0'))
          // Tokens available when negative means over allocation
          const tokensAvailable = stakes.tokensStaked
            .sub(stakes.tokensAllocated)
            .sub(stakes.tokensLocked)
          expect(tokensAvailable).eq(toGRT('-50'))

          const tx = staking.connect(indexer).unstake(tokensToUnstake)
          await expect(tx).revertedWith('Staking: not enough tokens available to unstake')
        })

        it('reject to slash zero tokens', async function() {
          const tokensToSlash = toGRT('0')
          const tokensToReward = toGRT('0')
          const tx = staking
            .connect(slasher)
            .slash(indexer.address, tokensToSlash, tokensToReward, me.address)
          await expect(tx).revertedWith('Slashing: cannot slash zero tokens')
        })

        it('reject to slash indexer if caller is not slasher', async function() {
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('10')
          const tx = staking
            .connect(me)
            .slash(indexer.address, tokensToSlash, tokensToReward, me.address)
          await expect(tx).revertedWith('Caller is not a Slasher')
        })

        it('reject to slash indexer if beneficiary is zero address', async function() {
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('10')
          const tx = staking
            .connect(slasher)
            .slash(indexer.address, tokensToSlash, tokensToReward, AddressZero)
          await expect(tx).revertedWith('Slashing: beneficiary must not be an empty address')
        })

        it('reject to slash indexer if reward is greater than slash amount', async function() {
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('200')
          const tx = staking
            .connect(slasher)
            .slash(indexer.address, tokensToSlash, tokensToReward, fisherman.address)
          await expect(tx).revertedWith('Slashing: reward cannot be higher than slashed amoun')
        })
      })

      describe('allocate', function() {
        it('should allocate', async function() {
          const tx = allocate(indexerStake)
          await expect(tx)
            .emit(staking, 'AllocationCreated')
            .withArgs(
              indexer.address,
              subgraphDeploymentID,
              await epochManager.currentEpoch(),
              indexerStake,
              channelID,
              channelPubKey,
              price,
            )
        })

        it('reject allocate more than available tokens', async function() {
          const tokensOverCapacity = indexerStake.add(toBN('1'))
          const tx = allocate(tokensOverCapacity)
          await expect(tx).revertedWith('Allocation: not enough tokens available to allocate')
        })

        it('reject allocate zero tokens', async function() {
          const zeroTokens = toGRT('0')
          const tx = allocate(zeroTokens)
          await expect(tx).revertedWith('Allocation: cannot allocate zero tokens')
        })

        it('reject allocate with invalid public key', async function() {
          const invalidChannelPubKey = computePublicKey(channelPubKey, true)
          const tx = staking
            .connect(indexer)
            .allocate(
              subgraphDeploymentID,
              toGRT('100'),
              invalidChannelPubKey,
              channelProxy.address,
              price,
            )
          await expect(tx).revertedWith('Allocation: invalid channel public key')
        })

        context('> when allocated', function() {
          beforeEach(async function() {
            await allocate(toGRT('10'))
          })

          // it('reject allocate again if not settled', async function() {
          //   const tokensToAllocate = toGRT('10')
          //   const tx = allocate(tokensToAllocate)
          //   await expect(tx).revertedWith('Allocation: cannot allocate if already allocated')
          // })

          it('reject allocate reusing a channel', async function() {
            const tokensToAllocate = toGRT('10')
            const subgraphDeploymentID = randomHexBytes()
            const tx = staking
              .connect(indexer)
              .allocate(
                subgraphDeploymentID,
                tokensToAllocate,
                channelPubKey,
                channelProxy.address,
                price,
              )
            await expect(tx).revertedWith('Allocation: channel ID already in use')
          })
        })
      })

      describe.only('collect', function() {
        beforeEach(async function() {
          // Create the allocation to be settled
          await allocate(tokensAllocated)

          // Fund wallets
          const tokensToFund = toGRT('100000')
          await grt.connect(governor).mint(channelProxy.address, tokensToFund)
          await grt.connect(channelProxy).approve(staking.address, tokensToFund)
        })

        it('reject collect if channel does not exist', async function() {
          const tx = staking.connect(other).collect(tokensToCollect)
          await expect(tx).revertedWith('Channel: does not exist')
        })

        it('should collect and distribute funds', async function() {
          // Before state
          const beforeAlloc = await staking.getAllocation(channelID)

          // Curate the subgraph from where we collect fees to get curation fees distributed
          const tokensToSignal = toGRT('100')
          await grt.connect(governor).mint(me.address, tokensToSignal)
          await grt.connect(me).approve(curation.address, tokensToSignal)
          await curation.connect(me).stake(subgraphDeploymentID, tokensToSignal)

          // Curation parameters
          const curationPercentage = toBN('200000') // 20%
          await staking.connect(governor).setCurationPercentage(curationPercentage)

          // Advance blocks to get the channel in epoch where it can be settled
          await advanceToNextEpoch(epochManager)

          // Calculate expected results
          const curationFees = tokensToCollect.mul(curationPercentage).div(MAX_PPM)
          const rebateFees = tokensToCollect.sub(curationFees) // calculate expected fees

          // Collect tokens from channel
          const tx = staking.connect(channelProxy).collect(tokensToCollect)
          await expect(tx)
            .emit(staking, 'AllocationCollected')
            .withArgs(
              indexer.address,
              subgraphDeploymentID,
              await epochManager.currentEpoch(),
              tokensToCollect,
              channelID,
              channelProxy.address,
              curationFees,
              rebateFees,
            )

          // After state
          const afterPool = await curation.pools(subgraphDeploymentID)
          const afterAlloc = await staking.getAllocation(channelID)

          // Check that curation reserves increased for the SubgraphDeployment
          expect(afterPool.tokens).eq(tokensToSignal.add(curationFees))
          // Verify allocation is updated and channel closed
          expect(afterAlloc.tokens).eq(beforeAlloc.tokens)
          expect(afterAlloc.createdAtEpoch).eq(beforeAlloc.createdAtEpoch)
          expect(afterAlloc.settledAtEpoch).eq(toBN('0'))
          expect(afterAlloc.collectedFees).eq(beforeAlloc.collectedFees.add(rebateFees))
        })

        it('should collect zero tokens', async function() {
          // Advance blocks to get the channel in epoch where it can be settled
          await advanceToNextEpoch(epochManager)
          // Settle zero tokens
          await staking.connect(channelProxy).collect(toBN('0'))
        })

        it.only('should collect from a settling channel but reject after dispute period', async function() {
          // Set channel dispute period to one epoch
          await staking.connect(governor).setChannelDisputeEpochs(toBN('1'))
          // Advance blocks to get the channel in epoch where it can be settled
          await advanceToNextEpoch(epochManager)
          // Settle the channel
          await staking.connect(indexer).settle(channelID)

          // Collect fees into the channel
          const tx1 = staking.connect(channelProxy).collect(tokensToCollect)
          await tx1

          // Advance blocks to get the channel in epoch where it can no longer collect funds
          await advanceToNextEpoch(epochManager)

          // Collect fees into the channel
          const tx2 = staking.connect(channelProxy).collect(tokensToCollect, { gasLimit: 8000000 })
          await expect(tx2).revertedWith(
            'Collect: channel cannot collect funds after dispute period',
          )
        })
      })

      describe('settle', function() {
        it('should settle a channel allocation', function() {})

        it('reject settle a non-existing channel allocation', function() {})

        it('reject settle before at least one epoch has passed', function() {})

        it('reject settle if not the owner of channel allocation', function() {})

        it('reject settle if channel allocation is already settled', function() {})
      })

      describe.only('claim', function() {
        // Claim and perform checks
        const shouldClaim = async function(channelID: string, restake: boolean) {
          // Advance blocks to get the channel in epoch where it can be claimed
          await advanceToNextEpoch(epochManager)

          // Before state
          const beforeAlloc = await staking.allocations(channelID)
          const beforeRebatePool = await staking.rebates(beforeAlloc.settledAtEpoch)

          // Claim rebates
          const currentEpoch = await epochManager.currentEpoch()
          const tx = staking.connect(indexer).claim(channelID, restake)
          await expect(tx)
            .emit(staking, 'RebateClaimed')
            .withArgs(
              indexer.address,
              subgraphDeploymentID,
              currentEpoch,
              beforeAlloc.settledAtEpoch,
              beforeAlloc.collectedFees,
              beforeRebatePool.settlementsCount.sub(toBN('1')),
              toGRT('0'),
            )

          // Verify the settlement is consumed when claimed and rebate pool updated
          const afterRebatePool = await staking.rebates(beforeAlloc.settledAtEpoch)
          expect(afterRebatePool.settlementsCount).eq(
            beforeRebatePool.settlementsCount.sub(toBN('1')),
          )
          if (afterRebatePool.settlementsCount.eq(toBN('0'))) {
            // Rebate pool is empty and then pruned
            expect(afterRebatePool.allocation).eq(toBN('0'))
            expect(afterRebatePool.fees).eq(toBN('0'))
          } else {
            // There are still more settlements in the rebate
            expect(afterRebatePool.allocation).eq(beforeRebatePool.allocation)
            expect(afterRebatePool.fees).eq(beforeRebatePool.fees.sub(beforeAlloc.collectedFees))
          }
        }

        beforeEach(async function() {
          // Create the allocation to be settled and claimed
          await allocate(tokensAllocated)
          await grt.connect(governor).mint(channelProxy.address, tokensToCollect)
          await grt.connect(channelProxy).approve(staking.address, tokensToCollect)

          // Advance blocks to get the channel in epoch where it can be settled
          await advanceToNextEpoch(epochManager)
        })

        it('reject claim if channel allocation is not settled', async function() {
          const tx = staking.connect(indexer).claim(channelID, false)
          await expect(tx).revertedWith('Rebate: channel must be settled')
        })

        it('reject claim for non-existing channel allocation', async function() {
          // Advance blocks to get the channel in epoch where it can be claimed
          await advanceToNextEpoch(epochManager)

          const invalidChannelID = randomHexBytes(20)
          const tx = staking.connect(indexer).claim(invalidChannelID, false)
          await expect(tx).revertedWith('Rebate: channel does not exist')
        })

        // it('should claim rebate of zero tokens', async function() {
        //   // Before state
        //   const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
        //   const beforeIndexerTokens = await grt.balanceOf(indexer.address)

        //   // Settle zero tokens
        //   const tx1 = await staking.connect(channelProxy).collect(toBN('0'))
        //   const receipt1 = await tx1.wait()
        //   const event1: Event = receipt1.events.pop()
        //   const rebateEpoch = event1.args['epoch']

        //   // Claim with no restake
        //   await shouldClaim(rebateEpoch, false, toBN('0'))

        //   // After state
        //   const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
        //   const afterIndexerTokens = await grt.balanceOf(indexer.address)

        //   // Verify that both stake and transferred tokens did not change
        //   expect(afterIndexerStake).eq(beforeIndexerStake)
        //   expect(afterIndexerTokens).eq(beforeIndexerTokens)
        // })

        context('> when settled', function() {
          beforeEach(async function() {
            // Collect some funds
            await staking.connect(channelProxy).collect(tokensToCollect)

            // Settle the allocation
            await staking.connect(indexer).settle(channelID)
          })

          it('reject claim if channelDisputeEpoch has not passed', async function() {
            const tx = staking.connect(indexer).claim(channelID, false)
            await expect(tx).revertedWith('Rebate: need to wait channel dispute period')
          })

          it('should claim rebate', async function() {
            // Before state
            const beforeIndexerTokens = await grt.balanceOf(indexer.address)

            // Claim with no restake
            await shouldClaim(channelID, false)

            // Verify that the claimed tokens are transferred to the indexer
            const afterIndexerTokens = await grt.balanceOf(indexer.address)
            expect(afterIndexerTokens).eq(beforeIndexerTokens.add(tokensToCollect))
          })

          it('should claim rebate with restake', async function() {
            // Before state
            const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

            // Claim with restake
            await shouldClaim(channelID, true)

            // Verify that the claimed tokens are restaked
            const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
            expect(afterIndexerStake).eq(beforeIndexerStake.add(tokensToCollect))
          })
        })
      })
    })
  })
})

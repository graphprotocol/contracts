import { expect, use } from 'chai'
import { constants, utils, BigNumber, Event, Wallet } from 'ethers'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import * as deployment from '../lib/deployment'
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
  const tokensToSettle = toGRT('100')

  beforeEach(async function() {
    // Deploy epoch contract
    epochManager = await deployment.deployEpochManager(governor.address)

    // Deploy graph token
    grt = await deployment.deployGRT(governor.address)

    // Deploy curation contract
    curation = await deployment.deployCuration(governor.address, grt.address)

    // Deploy staking contract
    staking = await deployment.deployStaking(
      governor,
      grt.address,
      epochManager.address,
      curation.address,
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
    const shouldStake = async function(indexerStake: BigNumber) {
      // Setup
      const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

      // Stake
      const tx = stake(indexerStake)
      await expect(tx)
        .to.emit(staking, 'StakeDeposited')
        .withArgs(indexer.address, indexerStake)

      // State updated
      const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
      expect(afterIndexerStake).to.eq(beforeIndexerStake.add(indexerStake))
    }

    beforeEach(async function() {
      // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
      await grt.connect(governor).mint(indexer.address, indexerTokens)
      await grt.connect(indexer).approve(staking.address, indexerTokens)
    })

    describe('hasStake', function() {
      it('should not have stakes', async function() {
        expect(await staking.hasStake(indexer.address)).to.be.eq(false)
      })
    })

    describe('stake', function() {
      it('should stake tokens', async function() {
        await shouldStake(indexerStake)
      })

      it('reject stake zero tokens', async function() {
        const tx = stake(toBN('0'))
        await expect(tx).to.be.revertedWith('Staking: cannot stake zero tokens')
      })
    })

    describe('unstake', function() {
      it('reject unstake tokens', async function() {
        const tokensToUnstake = toGRT('2')
        const tx = staking.connect(indexer).unstake(tokensToUnstake)
        await expect(tx).to.be.revertedWith('Staking: indexer has no stakes')
      })
    })

    describe('allocate', function() {
      it('reject allocate', async function() {
        const indexerStake = toGRT('100')
        const tx = allocate(indexerStake)
        await expect(tx).to.be.revertedWith('Allocation: indexer has no stakes')
      })
    })

    describe('slash', function() {
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
        await stake(indexerStake)
      })

      describe('hasStake', function() {
        it('should have stakes', async function() {
          expect(await staking.hasStake(indexer.address)).to.be.eq(true)
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
            .to.emit(staking, 'StakeLocked')
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
          expect(expectedLockedUntil).to.eq(tokensLockedUntil2)
        })

        it('reject unstake more than available tokens', async function() {
          const tokensOverCapacity = indexerStake.add(toBN('1'))
          const tx = staking.connect(indexer).unstake(tokensOverCapacity)
          await expect(tx).to.be.revertedWith('Staking: not enough tokens available to unstake')
        })
      })

      describe('withdraw', function() {
        it('should withdraw if tokens available', async function() {
          // Unstake
          const tokensToUnstake = toGRT('10')
          const tx1 = await staking.connect(indexer).unstake(tokensToUnstake)
          const receipt = await tx1.wait()
          const event: Event = receipt.events.pop()
          const tokensLockedUntil = event.args[2]

          // Withdraw on locking period (should fail)
          const tx2 = staking.connect(indexer).withdraw()
          await expect(tx2).to.be.revertedWith('Staking: no tokens available to withdraw')

          // Move forward
          await advanceBlockTo(tokensLockedUntil)

          // Withdraw after locking period (all good)
          const beforeBalance = await grt.balanceOf(indexer.address)
          await staking.connect(indexer).withdraw()
          const afterBalance = await grt.balanceOf(indexer.address)
          expect(afterBalance).to.eq(beforeBalance.add(tokensToUnstake))
        })

        it('reject withdraw if no tokens available', async function() {
          const tx = staking.connect(indexer).withdraw()
          await expect(tx).to.be.revertedWith('Staking: no tokens available to withdraw')
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
          expect(stakes.tokensStaked).to.eq(beforeTokensStaked.sub(tokensToSlash))
          // All allocated tokens should be untouched
          expect(stakes.tokensAllocated).to.eq(tokensToAllocate)
          // All locked tokens need to be consumed from the stake
          expect(stakes.tokensLocked).to.eq(toBN('0'))
          expect(stakes.tokensLockedUntil).to.eq(toBN('0'))
          // Tokens available when negative means over allocation
          const tokensAvailable = stakes.tokensStaked
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

      describe('allocate', function() {
        it('should allocate', async function() {
          const tx = allocate(indexerStake)
          await expect(tx)
            .to.emit(staking, 'AllocationCreated')
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
          await expect(tx).to.be.revertedWith('Allocation: not enough tokens available to allocate')
        })

        it('reject allocate zero tokens', async function() {
          const zeroTokens = toGRT('0')
          const tx = allocate(zeroTokens)
          await expect(tx).to.be.revertedWith('Allocation: cannot allocate zero tokens')
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
          await expect(tx).to.be.revertedWith('Allocation: invalid channel public key')
        })

        context('> when allocated', function() {
          beforeEach(async function() {
            await allocate(toGRT('10'))
          })

          it('reject allocate again if not settled', async function() {
            const tokensToAllocate = toGRT('10')
            const tx = allocate(tokensToAllocate)
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
                channelPubKey,
                channelProxy.address,
                price,
              )
            await expect(tx).to.be.revertedWith('Allocation: channel ID already in use')
          })
        })
      })

      describe('settle', function() {
        beforeEach(async function() {
          // Create the allocation to be settled
          await allocate(tokensAllocated)
          await grt.connect(governor).mint(channelProxy.address, tokensToSettle)
          await grt.connect(channelProxy).approve(staking.address, tokensToSettle)
        })

        it('should settle and distribute funds', async function() {
          const beforeStake = await staking.stakes(indexer.address)
          const beforeAlloc = await staking.getAllocation(indexer.address, subgraphDeploymentID)

          // Curate the subgraph to be settled to get curation fees distributed
          const tokensToSignal = toGRT('100')
          await grt.connect(governor).mint(me.address, tokensToSignal)
          await grt.connect(me).approve(curation.address, tokensToSignal)
          await curation.connect(me).stake(subgraphDeploymentID, tokensToSignal)

          // Curation parameters
          const curationPercentage = toBN('200000') // 20%
          await staking.connect(governor).setCurationPercentage(curationPercentage)

          // Advance blocks to get the channel in epoch where it can be settled
          await advanceToNextEpoch(epochManager)

          // Get epoch information
          const result = await epochManager.epochsSince(beforeAlloc.createdAtEpoch)
          const epochs = result[0].add(toBN('1'))
          const settlementEpoch = result[1].add(toBN('1'))

          // Calculate expected results
          const curationFees = tokensToSettle.mul(curationPercentage).div(MAX_PPM)
          const rebateFees = tokensToSettle.sub(curationFees) // calculate expected fees
          const effectiveAlloc = tokensAllocated.mul(epochs) // effective allocation

          // Settle
          const tx = staking.connect(channelProxy).settle(tokensToSettle)
          await expect(tx)
            .to.emit(staking, 'AllocationSettled')
            .withArgs(
              indexer.address,
              subgraphDeploymentID,
              settlementEpoch,
              tokensToSettle,
              channelID,
              channelProxy.address,
              curationFees,
              rebateFees,
              effectiveAlloc,
            )

          // Check that curation reserves increased for that SubgraphDeployment
          const afterPool = await curation.pools(subgraphDeploymentID)
          expect(afterPool.tokens).to.eq(tokensToSignal.add(curationFees))

          // Verify stake is updated
          const afterStake = await staking.stakes(indexer.address)
          expect(afterStake.tokensAllocated).to.eq(
            beforeStake.tokensAllocated.sub(beforeAlloc.tokens),
          )

          // Verify allocation is updated and channel closed
          const afterAlloc = await staking.getAllocation(indexer.address, subgraphDeploymentID)
          expect(afterAlloc.tokens).to.eq(toBN('0'))
          expect(afterAlloc.createdAtEpoch).to.eq(toBN('0'))
          expect(afterAlloc.channelID).to.be.eq(AddressZero)

          // Verify rebate information is stored
          const settlement = await staking.getSettlement(
            settlementEpoch,
            indexer.address,
            subgraphDeploymentID,
          )
          expect(settlement.fees).to.eq(rebateFees)
          expect(settlement.allocation).to.eq(effectiveAlloc)
        })

        it('should settle zero tokens', async function() {
          // Advance blocks to get the channel in epoch where it can be settled
          await advanceToNextEpoch(epochManager)

          // Settle zero tokens
          await staking.connect(channelProxy).settle(toBN('0'))

          // TODO: check AllocationSettled emitted
        })

        it('reject settle if channel does not exist', async function() {
          const tx = staking.connect(other).settle(tokensToSettle)
          await expect(tx).to.be.revertedWith('Channel: does not exist')
        })

        it('reject settle from an already settled channel', async function() {
          // Advance blocks to get the channel in epoch where it can be settled
          await advanceToNextEpoch(epochManager)

          // Settle the channel
          await staking.connect(channelProxy).settle(tokensToSettle.div(toBN('2')))

          // Settle the same channel to force an error
          const tx = staking.connect(channelProxy).settle(tokensToSettle.div(toBN('2')))
          await expect(tx).to.revertedWith('Channel: does not exist')
        })

        it('reject settle if an epoch has not passed', async function() {
          const tx = staking.connect(channelProxy).settle(tokensToSettle)
          await expect(tx).to.be.revertedWith('Channel: Can only settle after one epoch passed')
        })
      })

      describe('claim', function() {
        // Claim and perform checks
        const shouldClaim = async function(
          rebateEpoch: BigNumber,
          restake: boolean,
          tokensSettled: BigNumber,
        ) {
          // Advance blocks to get the channel in epoch where it can be claimed
          await advanceToNextEpoch(epochManager)

          const beforeRebatePool = await staking.rebates(rebateEpoch)

          // Claim rebates
          const currentEpoch = await epochManager.currentEpoch()
          const tx = staking.connect(indexer).claim(rebateEpoch, subgraphDeploymentID, restake)
          await expect(tx)
            .to.emit(staking, 'RebateClaimed')
            .withArgs(
              indexer.address,
              subgraphDeploymentID,
              currentEpoch,
              rebateEpoch,
              tokensSettled,
              beforeRebatePool.settlementsCount.sub(toBN('1')),
              toGRT('0'),
            )

          // Verify the settlement is consumed when claimed and rebate pool updated
          const afterRebatePool = await staking.rebates(rebateEpoch)
          expect(afterRebatePool.settlementsCount).to.eq(
            beforeRebatePool.settlementsCount.sub(toBN('1')),
          )
          if (afterRebatePool.settlementsCount.eq(toBN('0'))) {
            // Rebate pool is empty and then pruned
            expect(afterRebatePool.allocation).to.eq(toBN('0'))
            expect(afterRebatePool.fees).to.eq(toBN('0'))
          } else {
            // There are still more settlements in the rebate
            expect(afterRebatePool.allocation).to.eq(beforeRebatePool.allocation)
            expect(afterRebatePool.fees).to.eq(beforeRebatePool.fees.sub(tokensSettled))
          }
        }

        beforeEach(async function() {
          // Create the allocation to be settled
          await allocate(tokensAllocated)
          await grt.connect(governor).mint(channelProxy.address, tokensToSettle)
          await grt.connect(channelProxy).approve(staking.address, tokensToSettle)

          // Advance blocks to get the channel in epoch where it can be settled
          await advanceToNextEpoch(epochManager)
        })

        it('reject claim if channelDisputeEpoch has not passed', async function() {
          const currentEpoch = await epochManager.currentEpoch()
          const tx = staking.connect(indexer).claim(currentEpoch, subgraphDeploymentID, false)
          await expect(tx).to.be.revertedWith('Rebate: need to wait channel dispute period')
        })

        it('reject claim when no settlement available for that epoch', async function() {
          const currentEpoch = await epochManager.currentEpoch()
          const subgraphDeploymentID = randomHexBytes()

          // Advance blocks to get the channel in epoch where it can be claimed
          await advanceToNextEpoch(epochManager)

          const tx = staking.connect(indexer).claim(currentEpoch, subgraphDeploymentID, false)
          await expect(tx).to.be.revertedWith('Rebate: settlement does not exist')
        })

        it('should claim rebate of zero tokens', async function() {
          // Setup
          const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
          const beforeIndexerTokens = await grt.balanceOf(indexer.address)

          // Settle zero tokens
          const tx1 = await staking.connect(channelProxy).settle(toBN('0'))
          const receipt1 = await tx1.wait()
          const event1: Event = receipt1.events.pop()
          const rebateEpoch = event1.args['epoch']

          // Claim with no restake
          await shouldClaim(rebateEpoch, false, toBN('0'))

          // Verify that both stake and transferred tokens did not change
          const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
          const afterIndexerTokens = await grt.balanceOf(indexer.address)
          expect(afterIndexerStake).to.eq(beforeIndexerStake)
          expect(afterIndexerTokens).to.eq(beforeIndexerTokens)
        })

        context('> when settled', function() {
          let rebateEpoch

          beforeEach(async function() {
            // Settle
            const tx1 = await staking.connect(channelProxy).settle(tokensToSettle)
            const receipt1 = await tx1.wait()
            const event1: Event = receipt1.events.pop()
            rebateEpoch = event1.args['epoch']
          })

          it('should claim rebate', async function() {
            const beforeIndexerTokens = await grt.balanceOf(indexer.address)

            // Claim with no restake
            await shouldClaim(rebateEpoch, false, tokensToSettle)

            // Verify that the claimed tokens are transferred to the indexer
            const afterIndexerTokens = await grt.balanceOf(indexer.address)
            expect(afterIndexerTokens).to.eq(beforeIndexerTokens.add(tokensToSettle))
          })

          it('should claim rebate with restake', async function() {
            const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

            // Claim with restake
            await shouldClaim(rebateEpoch, true, tokensToSettle)

            // Verify that the claimed tokens are restaked
            const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
            expect(afterIndexerStake).to.eq(beforeIndexerStake.add(tokensToSettle))
          })
        })
      })
    })
  })
})

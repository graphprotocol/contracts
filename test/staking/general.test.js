const BN = web3.utils.BN
const { expect } = require('chai')
const { constants, expectRevert, expectEvent, time } = require('@openzeppelin/test-helpers')
const { ZERO_ADDRESS } = constants

// helpers
const deployment = require('../lib/deployment')
const helpers = require('../lib/testHelpers')

const MAX_PPM = new BN('1000000')

function weightedAverage(valueA, valueB, periodA, periodB) {
  return periodA
    .mul(valueA)
    .add(periodB.mul(valueB))
    .div(valueA.add(valueB))
}

function toGRT(value) {
  return web3.utils.toWei(new BN(value))
}

contract('Staking', ([me, other, governor, indexer, slasher, fisherman]) => {
  beforeEach(async function() {
    // Deploy epoch contract
    this.epochManager = await deployment.deployEpochManagerContract(governor, { from: me })

    // Deploy graph token
    this.grt = await deployment.deployGRT(governor, {
      from: me,
    })

    // Deploy curation contract
    this.curation = await deployment.deployCurationContract(governor, this.grt.address, {
      from: me,
    })

    // Deploy staking contract
    this.staking = await deployment.deployStakingContract(
      governor,
      this.grt.address,
      this.epochManager.address,
      this.curation.address,
      { from: me },
    )

    // Set slasher
    await this.staking.setSlasher(slasher, true, { from: governor })

    // Set staking as distributor of funds to curation
    await this.curation.setStaking(this.staking.address, { from: governor })

    // Helpers
    this.advanceToNextEpoch = async () => {
      const currentBlock = await time.latestBlock()
      const epochLength = await this.epochManager.epochLength()
      const nextEpochBlock = currentBlock.add(epochLength)
      await time.advanceBlockTo(nextEpochBlock)
    }
  })

  describe('configuration', function() {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await this.staking.governor()).to.eq(governor)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await this.staking.token()).to.eq(this.grt.address)
    })

    describe('setSlasher', function() {
      it('should set `slasher`', async function() {
        expect(await this.staking.slashers(me)).to.be.eq(false)
        await this.staking.setSlasher(me, true, { from: governor })
        expect(await this.staking.slashers(me)).to.be.eq(true)
      })

      it('reject set `slasher` if not allowed', async function() {
        await expectRevert(
          this.staking.setSlasher(me, true, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('channelDisputeEpochs', function() {
      it('should set `channelDisputeEpochs`', async function() {
        const newValue = new BN('5')
        await this.staking.setChannelDisputeEpochs(newValue, { from: governor })
        expect(await this.staking.channelDisputeEpochs()).to.be.bignumber.eq(newValue)
      })

      it('reject set `channelDisputeEpochs` if not allowed', async function() {
        const newValue = new BN('5')
        await expectRevert(
          this.staking.setChannelDisputeEpochs(newValue, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('curation', function() {
      it('should set `curation`', async function() {
        // Set right in the constructor
        expect(await this.staking.curation()).to.eq(this.curation.address)

        await this.staking.setCuration(ZERO_ADDRESS, { from: governor })
        expect(await this.staking.curation()).to.eq(ZERO_ADDRESS)
      })

      it('reject set `curation` if not allowed', async function() {
        await expectRevert(
          this.staking.setChannelDisputeEpochs(ZERO_ADDRESS, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('curationPercentage', function() {
      it('should set `curationPercentage`', async function() {
        const newValue = new BN('5')
        await this.staking.setCurationPercentage(newValue, { from: governor })
        expect(await this.staking.curationPercentage()).to.be.bignumber.eq(newValue)
      })

      it('reject set `curationPercentage` if out of bounds', async function() {
        await expectRevert(
          this.staking.setCurationPercentage(MAX_PPM.add(new BN('1')), {
            from: governor,
          }),
          'Curation percentage must be below or equal to MAX_PPM',
        )
      })

      it('reject set `curationPercentage` if not allowed', async function() {
        await expectRevert(
          this.staking.setCurationPercentage(50, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('maxAllocationEpochs', function() {
      it('should set `maxAllocationEpochs`', async function() {
        const newValue = new BN('5')
        await this.staking.setMaxAllocationEpochs(newValue, { from: governor })
        expect(await this.staking.maxAllocationEpochs()).to.be.bignumber.eq(newValue)
      })

      it('reject set `maxAllocationEpochs` if not allowed', async function() {
        const newValue = new BN('5')
        await expectRevert(
          this.staking.setMaxAllocationEpochs(newValue, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('thawingPeriod', function() {
      it('should set `thawingPeriod`', async function() {
        const newValue = new BN('5')
        await this.staking.setThawingPeriod(newValue, { from: governor })
        expect(await this.staking.thawingPeriod()).to.be.bignumber.eq(newValue)
      })

      it('reject set `thawingPeriod` if not allowed', async function() {
        const newValue = new BN('5')
        await expectRevert(
          this.staking.setThawingPeriod(newValue, { from: other }),
          'Only Governor can call',
        )
      })
    })
  })

  describe('staking', function() {
    beforeEach(async function() {
      this.subgraphID = helpers.randomSubgraphId()
      this.channelPubKey =
        '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'
      this.channelID = '0x6367E9dD7641e0fF221740b57B8C730031d72530'

      // Give some funds to the indexer
      this.indexerTokens = toGRT('1000')
      await this.grt.mint(indexer, this.indexerTokens, {
        from: governor,
      })
      // Approve staking contract to use funds on indexer behalf
      await this.grt.approve(this.staking.address, this.indexerTokens, { from: indexer })

      // Helpers
      this.stake = async function(tokens) {
        return this.staking.stake(tokens, { from: indexer })
      }
      this.allocate = function(tokens) {
        return this.staking.allocate(this.subgraphID, tokens, this.channelPubKey, {
          from: indexer,
        })
      }
    })

    context('> when not staked', function() {
      describe('hasStake()', function() {
        it('should not have stakes', async function() {
          expect(await this.staking.hasStake(indexer)).to.be.eq(false)
        })
      })

      describe('stake()', function() {
        it('should stake tokens', async function() {
          const indexerStake = toGRT('100')

          // Stake
          await this.stake(indexerStake)
          const tokens1 = await this.staking.getIndexerStakeTokens(indexer)
          expect(tokens1).to.be.bignumber.eq(indexerStake)
        })
      })

      describe('unstake()', function() {
        it('reject unstake tokens', async function() {
          const tokensToUnstake = toGRT('2')
          await expectRevert(
            this.staking.unstake(tokensToUnstake, { from: indexer }),
            'Staking: indexer has no stakes',
          )
        })
      })

      describe('allocate()', function() {
        it('reject allocate to subgraph', async function() {
          const indexerStake = toGRT('100')
          await expectRevert(this.allocate(indexerStake), 'Allocation: indexer has no stakes')
        })
      })

      describe('slash()', function() {
        it('reject slash indexer', async function() {
          const tokensToSlash = toGRT('10')
          const tokensToReward = toGRT('10')

          await expectRevert(
            this.staking.slash(indexer, tokensToSlash, tokensToReward, fisherman, {
              from: slasher,
            }),
            'Slashing: indexer has no stakes',
          )
        })
      })
    })

    context('> when staked', function() {
      beforeEach(async function() {
        // Stake
        this.indexerStake = toGRT('100')
        await this.stake(this.indexerStake)
      })

      describe('hasStake()', function() {
        it('should have stakes', async function() {
          expect(await this.staking.hasStake(indexer)).to.be.eq(true)
        })
      })

      describe('stake()', function() {
        it('should allow re-staking', async function() {
          // Re-stake
          const { tx } = await this.stake(this.indexerStake)
          const tokens2 = await this.staking.getIndexerStakeTokens(indexer)
          expect(tokens2).to.be.bignumber.eq(this.indexerStake.add(this.indexerStake))
          expectEvent.inTransaction(tx, this.staking.constructor, 'StakeDeposited', {
            indexer: indexer,
            tokens: this.indexerStake,
          })
        })
      })

      describe('unstake()', function() {
        it('should unstake and lock tokens for thawing period', async function() {
          const tokensToUnstake = toGRT('2')
          const thawingPeriod = await this.staking.thawingPeriod()
          const currentBlock = await time.latestBlock()
          const until = currentBlock.add(thawingPeriod).add(new BN('1'))

          const { logs } = await this.staking.unstake(tokensToUnstake, { from: indexer })
          expectEvent.inLogs(logs, 'StakeLocked', {
            indexer: indexer,
            tokens: tokensToUnstake,
            until: until,
          })
        })

        it('should unstake and lock tokens for (weighted avg) thawing period if repeated', async function() {
          const tokensToUnstake = toGRT('10')
          const thawingPeriod = await this.staking.thawingPeriod()

          // Unstake (1)
          let r = await this.staking.unstake(tokensToUnstake, { from: indexer })
          const tokensLockedUntil1 = r.logs[0].args.until

          // Move forward
          await time.advanceBlockTo(tokensLockedUntil1)

          // Calculate locking time for tokens taking into account the previous unstake request
          const currentBlock = await time.latestBlock()
          const lockingPeriod = weightedAverage(
            tokensToUnstake,
            tokensToUnstake,
            tokensLockedUntil1.sub(currentBlock),
            thawingPeriod,
          )
          const expectedLockedUntil = currentBlock.add(lockingPeriod).add(new BN('1'))

          // Unstake (2)
          r = await this.staking.unstake(tokensToUnstake, { from: indexer })
          const tokensLockedUntil2 = r.logs[0].args.until
          expect(expectedLockedUntil).to.be.bignumber.eq(tokensLockedUntil2)
        })

        it('reject unstake more than available tokens', async function() {
          const tokensOverCapacity = this.indexerStake.add(new BN('1'))
          await expectRevert(
            this.staking.unstake(tokensOverCapacity, { from: indexer }),
            'Staking: not enough tokens available to unstake',
          )
        })
      })

      describe('withdraw()', function() {
        it('should withdraw if tokens available', async function() {
          // Unstake
          const tokensToUnstake = toGRT('10')
          const { logs } = await this.staking.unstake(tokensToUnstake, { from: indexer })
          const tokensLockedUntil = logs[0].args.until

          // Withdraw on locking period (should fail)
          await expectRevert(
            this.staking.withdraw({ from: indexer }),
            'Staking: no tokens available to withdraw',
          )

          // Move forward
          await time.advanceBlockTo(tokensLockedUntil)

          // Withdraw after locking period (all good)
          const balanceBefore = await this.grt.balanceOf(indexer)
          await this.staking.withdraw({ from: indexer })
          const balanceAfter = await this.grt.balanceOf(indexer)
          expect(balanceAfter).to.be.bignumber.eq(balanceBefore.add(tokensToUnstake))
        })

        it('reject withdraw if no tokens available', async function() {
          await expectRevert(
            this.staking.withdraw({ from: indexer }),
            'Staking: no tokens available to withdraw',
          )
        })
      })

      describe('slash()', function() {
        before(function() {
          // This function tests slashing behaviour under different conditions
          this.shouldSlash = async function(indexer, tokensToSlash, tokensToReward, fisherman) {
            // Before
            const beforeTotalSupply = await this.grt.totalSupply()
            const beforeFishermanTokens = await this.grt.balanceOf(fisherman)
            const beforeIndexerStake = await this.staking.getIndexerStakeTokens(indexer)

            // Slash indexer
            const tokensToBurn = tokensToSlash.sub(tokensToReward)
            const { logs } = await this.staking.slash(
              indexer,
              tokensToSlash,
              tokensToReward,
              fisherman,
              { from: slasher },
            )

            // After
            const afterTotalSupply = await this.grt.totalSupply()
            const afterFishermanTokens = await this.grt.balanceOf(fisherman)
            const afterIndexerStake = await this.staking.getIndexerStakeTokens(indexer)

            // Check slashed tokens has been burned
            expect(afterTotalSupply).to.be.bignumber.eq(beforeTotalSupply.sub(tokensToBurn))
            // Check reward was given to the fisherman
            expect(afterFishermanTokens).to.be.bignumber.eq(
              beforeFishermanTokens.add(tokensToReward),
            )
            // Check indexer stake was updated
            expect(afterIndexerStake).to.be.bignumber.eq(beforeIndexerStake.sub(tokensToSlash))

            // Event emitted
            expectEvent.inLogs(logs, 'StakeSlashed', {
              indexer: indexer,
              tokens: tokensToSlash,
              reward: tokensToReward,
              beneficiary: fisherman,
            })
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

        it('should slash indexer even if it gets overallocated to subgraphs', async function() {
          // Initial stake
          const beforeTokensStaked = await this.staking.getIndexerStakeTokens(indexer)

          // Unstake partially, these tokens will be locked
          const tokensToUnstake = toGRT('10')
          await this.staking.unstake(tokensToUnstake, { from: indexer })

          // Allocate indexer stake
          const tokensToAllocate = toGRT('70')
          await this.allocate(tokensToAllocate)

          // State pre-slashing
          // helpers.logStake(await this.staking.stakes(indexer))
          // > Current state:
          // = Staked: 100
          // = Locked: 10
          // = Allocated: 70
          // = Available: 20 (staked - allocated - locked)

          // Even if all stake is allocated to subgraphs it should slash the indexer
          const tokensToSlash = toGRT('80')
          const tokensToReward = toGRT('0')
          await this.shouldSlash(indexer, tokensToSlash, tokensToReward, fisherman)

          // State post-slashing
          // helpers.logStake(await this.staking.stakes(indexer))
          // > Current state:
          // = Staked: 20
          // = Locked: 0
          // = Allocated: 70
          // = Available: -50 (staked - allocated - locked) => when tokens available becomes negative
          // we are overallocated, the staking contract will prevent unstaking or allocating until
          // the balance is restored by staking or unallocating

          const stakes = await this.staking.stakes(indexer)
          // Stake should be reduced by the amount slashed
          expect(stakes.tokensIndexer).to.be.bignumber.eq(beforeTokensStaked.sub(tokensToSlash))
          // All allocated tokens should be untouched
          expect(stakes.tokensAllocated).to.be.bignumber.eq(tokensToAllocate)
          // All locked tokens need to be consumed from the stake
          expect(stakes.tokensLocked).to.be.bignumber.eq(new BN('0'))
          expect(stakes.tokensLockedUntil).to.be.bignumber.eq(new BN('0'))
          // Tokens available when negative means over allocation
          const tokensAvailable = stakes.tokensIndexer
            .sub(stakes.tokensAllocated)
            .sub(stakes.tokensLocked)
          expect(tokensAvailable).to.be.bignumber.eq(toGRT('-50'))

          await expectRevert(
            this.staking.unstake(tokensToUnstake, { from: indexer }),
            'Staking: not enough tokens available to unstake',
          )
        })

        it('reject to slash indexer if sender is not slasher', async function() {
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('10')
          await expectRevert(
            this.staking.slash(indexer, tokensToSlash, tokensToReward, me, { from: me }),
            'Caller is not a Slasher',
          )
        })

        it('reject to slash indexer if beneficiary is zero address', async function() {
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('10')
          await expectRevert(
            this.staking.slash(indexer, tokensToSlash, tokensToReward, ZERO_ADDRESS, {
              from: slasher,
            }),
            'Slashing: beneficiary must not be an empty address',
          )
        })

        it('reject to slash indexer if reward is greater than slash amount', async function() {
          const tokensToSlash = toGRT('100')
          const tokensToReward = toGRT('200')
          await expectRevert(
            this.staking.slash(indexer, tokensToSlash, tokensToReward, fisherman, {
              from: slasher,
            }),
            'Slashing: reward cannot be higher than slashed amoun',
          )
        })
      })

      describe('allocate()', function() {
        context('> when subgraph not allocated', function() {
          it('should allocate to subgraph', async function() {
            const { logs } = await this.allocate(this.indexerStake)
            expectEvent.inLogs(logs, 'AllocationCreated', {
              indexer: indexer,
              subgraphID: this.subgraphID,
              epoch: await this.epochManager.currentEpoch(),
              tokens: this.indexerStake,
              channelID: this.channelID,
              channelPubKey: this.channelPubKey,
            })
          })

          it('reject allocate more than available tokens', async function() {
            const tokensOverCapacity = this.indexerStake.add(new BN('1'))
            await expectRevert(
              this.allocate(tokensOverCapacity),
              'Allocation: not enough tokens available to allocate',
            )
          })

          it('reject allocate zero tokens', async function() {
            const zeroTokens = toGRT('0')
            await expectRevert(this.allocate(zeroTokens), 'Allocation: cannot allocate zero tokens')
          })
        })

        context('> when subgraph allocated', function() {
          beforeEach(async function() {
            this.tokensAllocated = toGRT('10')
            await this.allocate(this.tokensAllocated)
          })

          it('reject allocate again if not settled', async function() {
            const tokensToAllocate = toGRT('10')
            await expectRevert(
              this.allocate(tokensToAllocate),
              'Allocation: cannot allocate if already allocated',
            )
          })

          it('reject allocate reusing a channel', async function() {
            const tokensToAllocate = toGRT('10')
            const subgraphID = helpers.randomSubgraphId()
            await expectRevert(
              this.staking.allocate(subgraphID, tokensToAllocate, this.channelPubKey, {
                from: indexer,
              }),
              'Allocation: channel ID already in use',
            )
          })
        })
      })

      describe('settle()', function() {
        beforeEach(async function() {
          this.tokensAllocated = toGRT('10')
          this.tokensToSettle = toGRT('100')
          await this.allocate(this.tokensAllocated)
          await this.grt.mint(me, this.tokensToSettle, { from: governor })
          await this.grt.approve(this.staking.address, this.tokensToSettle, { from: me })
        })

        it('should settle and distribute funds', async function() {
          const alloc = await this.staking.getAllocation(indexer, this.subgraphID)

          // Curate the subgraph to be settled to get curation fees distributed
          const tokensToSignal = toGRT('100')
          await this.grt.mint(me, tokensToSignal, { from: governor })
          await this.grt.approve(this.curation.address, tokensToSignal, { from: me })
          await this.curation.stake(this.subgraphID, tokensToSignal, { from: me })

          // Curation parameters
          const curationPercentage = new BN('200000') // 20%
          await this.staking.setCurationPercentage(curationPercentage, { from: governor })

          // Advance blocks to get the channel in epoch where it can be settled
          await this.advanceToNextEpoch()

          // Settle
          const { logs } = await this.staking.settle(this.channelID, this.tokensToSettle)

          // Get epoch information
          const result = await this.epochManager.epochsSince(alloc.createdAtEpoch)
          const epochs = result[0]
          const currentEpoch = result[1]

          // Calculate expected fees
          const curationFees = this.tokensToSettle.mul(curationPercentage).div(MAX_PPM)
          const rebateFees = this.tokensToSettle.sub(curationFees)

          // Calculate expected effective allocation
          const effectiveAlloc = this.tokensAllocated.mul(epochs)

          // Check that curation reserves increased for that subgraph
          const subgraphAfter = await this.curation.subgraphs(this.subgraphID)
          expect(subgraphAfter.tokens).to.be.bignumber.eq(tokensToSignal.add(curationFees))

          // Verify rebate information is stored
          const settlement = await this.staking.getSettlement(
            currentEpoch,
            indexer,
            this.subgraphID,
          )
          expect(settlement.fees).to.be.bignumber.eq(rebateFees)
          expect(settlement.allocation).to.be.bignumber.eq(effectiveAlloc)

          // Event emitted
          expectEvent.inLogs(logs, 'AllocationSettled', {
            indexer: indexer,
            subgraphID: this.subgraphID,
            epoch: currentEpoch,
            tokens: this.tokensToSettle,
            channelID: this.channelID,
            from: me,
            curationFees: curationFees,
            rebateFees: rebateFees,
            effectiveAllocation: effectiveAlloc,
          })
        })

        it('reject settle if channel does not exist', async function() {
          await expectRevert(
            this.staking.settle(ZERO_ADDRESS, this.tokensToSettle),
            'Channel: does not exist',
          )
        })

        it('reject settle if allocation does not have an active channel', async function() {
          // Advance blocks to get the channel in epoch where it can be settled
          await this.advanceToNextEpoch()

          // Settle the channel
          await this.staking.settle(this.channelID, this.tokensToSettle.div(new BN('2')))

          // Settle the same channel to force an error
          await expectRevert(
            this.staking.settle(this.channelID, this.tokensToSettle.div(new BN('2'))),
            'Channel: Must be active for settlement',
          )
        })

        it('reject settle using an already settled channel', async function() {
          const newChannelPubKey =
            '0x04f2ba8222e1dbe3ebe6a72bac637cfe7eb9ea282c6f3319fd239ca3c69a088aabcbbf2a4484c49fe86b3165c61b13922376435961cf83e7e756b1d3fe3ead0206'
          const channelID1 = this.channelID
          // const channelID2 = '0x564Ef40551c936Fa05B5dA63562F25cE99F88111'

          // Advance blocks to get the channel in epoch where it can be settled
          await this.advanceToNextEpoch()

          // Settle the channel
          await this.staking.settle(channelID1, this.tokensToSettle.div(new BN('2')))

          // We allocate to the same subgraph with different new channel
          await this.staking.allocate(this.subgraphID, this.tokensAllocated, newChannelPubKey, {
            from: indexer,
          })

          // Advance blocks to get the channel in epoch where it can be settled
          await this.advanceToNextEpoch()

          // Settle the channel using the old channel should be invalid
          await expectRevert(
            this.staking.settle(channelID1, this.tokensToSettle.div(new BN('2'))),
            'Channel: Cannot settle an already closed channel',
          )
        })

        it('reject settle if an epoch has not passed', async function() {
          await expectRevert(
            this.staking.settle(this.channelID, this.tokensToSettle),
            'Channel: Can only settle after one epoch passed',
          )
        })
      })

      describe('claim()', function() {
        beforeEach(async function() {
          this.tokensAllocated = toGRT('10')
          this.tokensToSettle = toGRT('100')
          await this.allocate(this.tokensAllocated)
          await this.grt.mint(me, this.tokensToSettle, { from: governor })
          await this.grt.approve(this.staking.address, this.tokensToSettle, { from: me })
        })

        it('should claim rebates', async function() {
          // Advance blocks to get the channel in epoch where it can be settled
          await this.advanceToNextEpoch()

          // Settle
          await this.staking.settle(this.channelID, this.tokensToSettle, { from: me })
          const rebateEpoch = await this.epochManager.currentEpoch()

          // Advance blocks to get the channel in epoch where the rebate can be claimed
          await this.advanceToNextEpoch()

          // Claim rebates
          const currentEpoch = await this.epochManager.currentEpoch()
          const { logs } = await this.staking.claim(rebateEpoch, this.subgraphID, false, {
            from: indexer,
          })

          // Event emitted
          expectEvent.inLogs(logs, 'RebateClaimed', {
            indexer: indexer,
            subgraphID: this.subgraphID,
            epoch: currentEpoch,
            forEpoch: rebateEpoch,
            tokens: this.tokensToSettle,
            settlements: new BN('0'),
          })
        })

        it('reject claim if channelDisputeEpoch has not passed', async function() {
          const rebateEpoch = await this.epochManager.currentEpoch()
          await expectRevert(
            this.staking.claim(rebateEpoch, this.subgraphID, { from: indexer }),
            'Rebate: need to wait channel dispute period',
          )
        })

        it('reject claim when no settlement available for that epoch', async function() {
          const rebateEpoch = await this.epochManager.currentEpoch()

          // Advance blocks to get the channel in epoch where it can be claimed
          await this.advanceToNextEpoch()

          await expectRevert(
            this.staking.claim(rebateEpoch, this.subgraphID, { from: indexer }),
            'Rebate: settlement does not exist',
          )
        })
      })
    })
  })
})

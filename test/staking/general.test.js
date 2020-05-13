const BN = web3.utils.BN
const { expect } = require('chai')
const { constants, expectRevert, expectEvent, time } = require('@openzeppelin/test-helpers')
const { ZERO_ADDRESS } = constants

// helpers
const deployment = require('../lib/deployment')
const helpers = require('../lib/testHelpers')

const MAX_PPM = 1000000

function weightedAverage(valueA, valueB, periodA, periodB) {
  return periodA
    .mul(valueA)
    .add(periodB.mul(valueB))
    .div(valueA.add(valueB))
}

contract('Staking', ([me, other, governor, indexNode, slasher, fisherman]) => {
  beforeEach(async function() {
    // Deploy epoch contract
    this.epochManager = await deployment.deployEpochManagerContract(governor, { from: me })

    // Deploy graph token
    this.graphToken = await deployment.deployGraphToken(governor, {
      from: me,
    })

    // Deploy curation contract
    this.curation = await deployment.deployCurationContract(governor, this.graphToken.address, {
      from: me,
    })

    // Deploy staking contract
    this.staking = await deployment.deployStakingContract(
      governor,
      this.graphToken.address,
      this.epochManager.address,
      this.curation.address,
      { from: me },
    )

    // Set slasher
    await this.staking.setSlasher(slasher, true, { from: governor })

    // Set staking as distributor of funds to curation
    await this.curation.setStaking(this.staking.address, { from: governor })
  })

  describe('configuration', function() {
    it('should set `governor`', async function() {
      // Set right in the constructor
      expect(await this.staking.governor()).to.eq(governor)
    })

    it('should set `graphToken`', async function() {
      // Set right in the constructor
      expect(await this.staking.token()).to.eq(this.graphToken.address)
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
        const newValue = new BN(5)
        await this.staking.setChannelDisputeEpochs(newValue, { from: governor })
        expect(await this.staking.channelDisputeEpochs()).to.be.bignumber.eq(newValue)
      })

      it('reject set `channelDisputeEpochs` if not allowed', async function() {
        const newValue = new BN(5)
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
        const newValue = new BN(5)
        await this.staking.setCurationPercentage(newValue, { from: governor })
        expect(await this.staking.curationPercentage()).to.be.bignumber.eq(newValue)
      })

      it('reject set `curationPercentage` if out of bounds', async function() {
        await expectRevert(
          this.staking.setCurationPercentage(MAX_PPM + 1, {
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

    describe('maxSettlementEpochs', function() {
      it('should set `maxSettlementEpochs`', async function() {
        const newValue = new BN(5)
        await this.staking.setMaxSettlementEpochs(newValue, { from: governor })
        expect(await this.staking.maxSettlementEpochs()).to.be.bignumber.eq(newValue)
      })

      it('reject set `maxSettlementEpochs` if not allowed', async function() {
        const newValue = new BN(5)
        await expectRevert(
          this.staking.setMaxSettlementEpochs(newValue, { from: other }),
          'Only Governor can call',
        )
      })
    })

    describe('thawingPeriod', function() {
      it('should set `thawingPeriod`', async function() {
        const newValue = new BN(5)
        await this.staking.setThawingPeriod(newValue, { from: governor })
        expect(await this.staking.thawingPeriod()).to.be.bignumber.eq(newValue)
      })

      it('reject set `thawingPeriod` if not allowed', async function() {
        const newValue = new BN(5)
        await expectRevert(
          this.staking.setThawingPeriod(newValue, { from: other }),
          'Only Governor can call',
        )
      })
    })
  })

  describe('token transfer', function() {
    it('reject calls to token received hook if not the GRT token contract', async function() {
      await expectRevert(
        this.staking.tokensReceived(indexNode, 10000, '0x0', {
          from: me,
        }),
        'Caller is not the GRT token contract',
      )
    })
  })

  describe('staking', function() {
    beforeEach(async function() {
      this.subgraphId = helpers.randomSubgraphIdHex0x()
      this.channelPubKey =
        '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'
      this.channelID = '0x6367E9dD7641e0fF221740b57B8C730031d72530'

      // Give some funds to the index node
      this.indexNodeTokens = web3.utils.toWei(new BN('1000'))
      await this.graphToken.mint(indexNode, this.indexNodeTokens, {
        from: governor,
      })

      // Helpers
      this.stake = async function(tokens) {
        const PAYMENT_PAYLOAD = '0x0'
        return this.graphToken.transferToTokenReceiver(
          this.staking.address,
          tokens,
          PAYMENT_PAYLOAD,
          { from: indexNode },
        )
      }
      this.allocate = function(tokens) {
        return this.staking.allocate(this.subgraphId, tokens, this.channelPubKey, {
          from: indexNode,
        })
      }
    })

    context('> when not staked', function() {
      describe('hasStake()', function() {
        it('should not have stakes', async function() {
          expect(await this.staking.hasStake(indexNode)).to.be.eq(false)
        })
      })

      describe('stake()', function() {
        it('should stake tokens', async function() {
          const indexNodeStake = web3.utils.toWei(new BN('100'))

          // Stake
          await this.stake(indexNodeStake)
          const tokens1 = await this.staking.getIndexNodeStakeTokens(indexNode)
          expect(tokens1).to.be.bignumber.eq(indexNodeStake)

          // Re-stake
          const { tx } = await this.stake(indexNodeStake)
          const tokens2 = await this.staking.getIndexNodeStakeTokens(indexNode)
          expect(tokens2).to.be.bignumber.eq(indexNodeStake.add(indexNodeStake))
          expectEvent.inTransaction(tx, this.staking.constructor, 'StakeDeposited', {
            indexNode: indexNode,
            tokens: indexNodeStake,
          })
        })
      })

      describe('unstake()', function() {
        it('reject unstake tokens', async function() {
          const tokensToUnstake = web3.utils.toWei(new BN('2'))
          await expectRevert(
            this.staking.unstake(tokensToUnstake, { from: indexNode }),
            'Staking: index node has no stakes',
          )
        })
      })

      describe('allocate()', function() {
        it('reject allocate to subgraph', async function() {
          const indexNodeStake = web3.utils.toWei(new BN('100'))
          await expectRevert(this.allocate(indexNodeStake), 'Allocation: index node has no stakes')
        })
      })

      describe('slash()', function() {
        it('reject slash indexer', async function() {
          const tokensToSlash = web3.utils.toWei(new BN('10'))
          const tokensToReward = web3.utils.toWei(new BN('10'))

          await expectRevert(
            this.staking.slash(indexNode, tokensToSlash, tokensToReward, fisherman, {
              from: slasher,
            }),
            'Slashing: index node has no stakes',
          )
        })
      })
    })

    context('> when staked', function() {
      beforeEach(async function() {
        // Stake
        this.indexNodeStake = web3.utils.toWei(new BN('100'))
        await this.stake(this.indexNodeStake)
      })

      describe('hasStake()', function() {
        it('should have stakes', async function() {
          expect(await this.staking.hasStake(indexNode)).to.be.eq(true)
        })
      })

      describe('unstake()', function() {
        it('should unstake and lock tokens for thawing period', async function() {
          const tokensToUnstake = web3.utils.toWei(new BN('2'))
          const thawingPeriod = await this.staking.thawingPeriod()
          const currentBlock = await time.latestBlock()
          const until = currentBlock.add(thawingPeriod).add(new BN(1))

          const { logs } = await this.staking.unstake(tokensToUnstake, { from: indexNode })
          expectEvent.inLogs(logs, 'StakeLocked', {
            indexNode: indexNode,
            tokens: tokensToUnstake,
            until: until,
          })
        })

        it('should unstake and lock tokens for (weighted avg) thawing period if repeated', async function() {
          const tokensToUnstake = web3.utils.toWei(new BN('10'))
          const thawingPeriod = await this.staking.thawingPeriod()

          // Unstake (1)
          let r = await this.staking.unstake(tokensToUnstake, { from: indexNode })
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
          const expectedLockedUntil = currentBlock.add(lockingPeriod).add(new BN(1))

          // Unstake (2)
          r = await this.staking.unstake(tokensToUnstake, { from: indexNode })
          const tokensLockedUntil2 = r.logs[0].args.until
          expect(expectedLockedUntil).to.be.bignumber.eq(tokensLockedUntil2)
        })

        it('reject unstake more than available tokens', async function() {
          const tokensOverCapacity = this.indexNodeStake.add(new BN(1))
          await expectRevert(
            this.staking.unstake(tokensOverCapacity, { from: indexNode }),
            'Staking: not enough tokens available to unstake',
          )
        })
      })

      describe('withdraw()', function() {
        it('should withdraw if tokens available', async function() {
          // Unstake
          const tokensToUnstake = web3.utils.toWei(new BN('10'))
          const { logs } = await this.staking.unstake(tokensToUnstake, { from: indexNode })
          const tokensLockedUntil = logs[0].args.until

          // Withdraw on locking period (should fail)
          await expectRevert(
            this.staking.withdraw({ from: indexNode }),
            'Staking: no tokens available to withdraw',
          )

          // Move forward
          await time.advanceBlockTo(tokensLockedUntil)

          // Withdraw after locking period (all good)
          const balanceBefore = await this.graphToken.balanceOf(indexNode)
          await this.staking.withdraw({ from: indexNode })
          const balanceAfter = await this.graphToken.balanceOf(indexNode)
          expect(balanceAfter).to.be.bignumber.eq(balanceBefore.add(tokensToUnstake))
        })

        it('reject withdraw if no tokens available', async function() {
          await expectRevert(
            this.staking.withdraw({ from: indexNode }),
            'Staking: no tokens available to withdraw',
          )
        })
      })

      describe('slash()', function() {
        before(function() {
          // This function tests slashing behaviour under different conditions
          this.shouldSlash = async function(indexNode, tokensToSlash, tokensToReward, fisherman) {
            // Before
            const beforeTotalSupply = await this.graphToken.totalSupply()
            const beforeFishermanTokens = await this.graphToken.balanceOf(fisherman)
            const beforeIndexerStake = await this.staking.getIndexNodeStakeTokens(indexNode)

            // Slash indexer
            const tokensToBurn = tokensToSlash.sub(tokensToReward)
            const { logs } = await this.staking.slash(
              indexNode,
              tokensToSlash,
              tokensToReward,
              fisherman,
              { from: slasher },
            )

            // After
            const afterTotalSupply = await this.graphToken.totalSupply()
            const afterFishermanTokens = await this.graphToken.balanceOf(fisherman)
            const afterIndexerStake = await this.staking.getIndexNodeStakeTokens(indexNode)

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
              indexNode: indexNode,
              tokens: tokensToSlash,
              reward: tokensToReward,
              beneficiary: fisherman,
            })
          }
        })

        it('should slash indexer and give reward to beneficiary slash>reward', async function() {
          // Slash indexer
          const tokensToSlash = web3.utils.toWei(new BN('100'))
          const tokensToReward = web3.utils.toWei(new BN('10'))

          await this.shouldSlash(indexNode, tokensToSlash, tokensToReward, fisherman)
        })

        it('should slash indexer and give reward to beneficiary slash=reward', async function() {
          // Slash indexer
          const tokensToSlash = web3.utils.toWei(new BN('10'))
          const tokensToReward = web3.utils.toWei(new BN('10'))

          await this.shouldSlash(indexNode, tokensToSlash, tokensToReward, fisherman)
        })

        it('should slash indexer even if it gets overallocated to subgraphs', async function() {
          // Initial stake
          const beforeTokensStaked = await this.staking.getIndexNodeStakeTokens(indexNode)

          // Unstake partially, these tokens will be locked
          const tokensToUnstake = web3.utils.toWei(new BN('10'))
          await this.staking.unstake(tokensToUnstake, { from: indexNode })

          // Allocate indexer stake
          const tokensToAllocate = web3.utils.toWei(new BN('70'))
          await this.allocate(tokensToAllocate)

          // State pre-slashing
          // helpers.logStake(await this.staking.stakes(indexNode))
          // > Current state:
          // = Staked: 100
          // = Locked: 10
          // = Allocated: 70
          // = Available: 20 (staked - allocated - locked)

          // Even if all stake is allocated to subgraphs it should slash the indexer
          const tokensToSlash = web3.utils.toWei(new BN('80'))
          const tokensToReward = web3.utils.toWei(new BN('0'))
          await this.shouldSlash(indexNode, tokensToSlash, tokensToReward, fisherman)

          // State post-slashing
          // helpers.logStake(await this.staking.stakes(indexNode))
          // > Current state:
          // = Staked: 20
          // = Locked: 0
          // = Allocated: 70
          // = Available: -50 (staked - allocated - locked) => when tokens available becomes negative
          // we are overallocated, the staking contract will prevent unstaking or allocating until
          // the balance is restored by staking or unallocating

          const stakes = await this.staking.stakes(indexNode)
          // Stake should be reduced by the amount slashed
          expect(stakes.tokensIndexNode).to.be.bignumber.eq(beforeTokensStaked.sub(tokensToSlash))
          // All allocated tokens should be untouched
          expect(stakes.tokensAllocated).to.be.bignumber.eq(tokensToAllocate)
          // All locked tokens need to be consumed from the stake
          expect(stakes.tokensLocked).to.be.bignumber.eq(new BN('0'))
          expect(stakes.tokensLockedUntil).to.be.bignumber.eq(new BN('0'))
          // Tokens available when negative means over allocation
          const tokensAvailable = stakes.tokensIndexNode
            .sub(stakes.tokensAllocated)
            .sub(stakes.tokensLocked)
          expect(tokensAvailable).to.be.bignumber.eq(web3.utils.toWei(new BN('-50')))

          await expectRevert(
            this.staking.unstake(tokensToUnstake, { from: indexNode }),
            'Staking: not enough tokens available to unstake',
          )
        })

        it('reject to slash indexer if sender is not slasher', async function() {
          const tokensToSlash = web3.utils.toWei(new BN('100'))
          const tokensToReward = web3.utils.toWei(new BN('10'))
          await expectRevert(
            this.staking.slash(indexNode, tokensToSlash, tokensToReward, me, { from: me }),
            'Caller is not a Slasher',
          )
        })

        it('reject to slash indexer if beneficiary is zero address', async function() {
          const tokensToSlash = web3.utils.toWei(new BN('100'))
          const tokensToReward = web3.utils.toWei(new BN('10'))
          await expectRevert(
            this.staking.slash(indexNode, tokensToSlash, tokensToReward, ZERO_ADDRESS, {
              from: slasher,
            }),
            'Slashing: beneficiary must not be an empty address',
          )
        })

        it('reject to slash indexer if reward is greater than slash amount', async function() {
          const tokensToSlash = web3.utils.toWei(new BN('100'))
          const tokensToReward = web3.utils.toWei(new BN('200'))
          await expectRevert(
            this.staking.slash(indexNode, tokensToSlash, tokensToReward, fisherman, {
              from: slasher,
            }),
            'Slashing: reward cannot be higher than slashed amoun',
          )
        })
      })

      describe('allocate()', function() {
        context('> when subgraph not allocated', function() {
          it('should allocate to subgraph', async function() {
            const { logs } = await this.allocate(this.indexNodeStake)
            expectEvent.inLogs(logs, 'AllocationCreated', {
              indexNode: indexNode,
              subgraphID: this.subgraphId,
              epoch: await this.epochManager.currentEpoch(),
              tokens: this.indexNodeStake,
              channelID: this.channelID,
              channelPubKey: this.channelPubKey,
            })
          })

          it('reject allocate more than available tokens', async function() {
            const tokensOverCapacity = this.indexNodeStake.add(new BN(1))
            await expectRevert(
              this.allocate(tokensOverCapacity),
              'Allocation: not enough tokens available to allocate',
            )
          })

          it('reject allocate zero tokens', async function() {
            const zeroTokens = web3.utils.toWei(new BN('0'))
            await expectRevert(this.allocate(zeroTokens), 'Allocation: cannot allocate zero tokens')
          })
        })

        context('> when subgraph allocated', function() {
          beforeEach(async function() {
            this.tokensAllocated = web3.utils.toWei(new BN('10'))
            await this.allocate(this.tokensAllocated)
          })

          it('reject allocate again if not settled', async function() {
            const tokensToAllocate = web3.utils.toWei(new BN('10'))
            await expectRevert(
              this.allocate(tokensToAllocate),
              'Allocation: cannot allocate if already allocated',
            )
          })
        })
      })
    })
  })
})

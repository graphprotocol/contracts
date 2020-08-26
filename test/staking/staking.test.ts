import { expect } from 'chai'
import { constants, BigNumber, Event } from 'ethers'

import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'

import {
  advanceBlockTo,
  getAccounts,
  randomHexBytes,
  latestBlock,
  toBN,
  toGRT,
  Account,
} from '../lib/testHelpers'

const { AddressZero } = constants

function weightedAverage(
  valueA: BigNumber,
  valueB: BigNumber,
  periodA: BigNumber,
  periodB: BigNumber,
) {
  return periodA.mul(valueA).add(periodB.mul(valueB)).div(valueA.add(valueB))
}

describe('Staking:Stakes', () => {
  let me: Account
  let governor: Account
  let indexer: Account
  let slasher: Account
  let fisherman: Account
  let channelProxy: Account

  let fixture: NetworkFixture

  let grt: GraphToken
  let staking: Staking

  // Test values
  const indexerTokens = toGRT('1000')
  const tokensToStake = toGRT('100')
  const subgraphDeploymentID = randomHexBytes()
  const channelPubKey =
    '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'
  const price = toGRT('0.01')

  // Allocate with test values
  const allocate = function (tokens: BigNumber) {
    return staking
      .connect(indexer.signer)
      .allocate(subgraphDeploymentID, tokens, channelPubKey, channelProxy.address, price)
  }

  // Stake and verify state change
  const shouldStake = async function (tokensToStake: BigNumber) {
    // Before state
    const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
    const beforeStakingBalance = await grt.balanceOf(staking.address)

    // Stake
    const tx = staking.connect(indexer.signer).stake(tokensToStake)
    await expect(tx).emit(staking, 'StakeDeposited').withArgs(indexer.address, tokensToStake)

    // After state
    const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
    const afterStakingBalance = await grt.balanceOf(staking.address)

    // State updated
    expect(afterIndexerStake).eq(beforeIndexerStake.add(tokensToStake))
    expect(afterStakingBalance).eq(beforeStakingBalance.add(tokensToStake))
  }

  before(async function () {
    ;[me, governor, indexer, slasher, fisherman, channelProxy] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ grt, staking } = await fixture.load(governor.signer, slasher.signer))

    // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
    await grt.connect(governor.signer).mint(indexer.address, indexerTokens)
    await grt.connect(indexer.signer).approve(staking.address, indexerTokens)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  context('> when not staked', function () {
    describe('hasStake', function () {
      it('should not have stakes', async function () {
        expect(await staking.hasStake(indexer.address)).eq(false)
      })
    })

    describe('stake', function () {
      it('reject stake zero tokens', async function () {
        const tx = staking.connect(indexer.signer).stake(toGRT('0'))
        await expect(tx).revertedWith('cannot stake zero tokens')
      })

      it('should stake tokens', async function () {
        await shouldStake(tokensToStake)
      })
    })

    describe('unstake', function () {
      it('reject unstake tokens', async function () {
        const tokensToUnstake = toGRT('2')
        const tx = staking.connect(indexer.signer).unstake(tokensToUnstake)
        await expect(tx).revertedWith('indexer has no stakes')
      })
    })

    describe('slash', function () {
      it('reject slash indexer', async function () {
        const tokensToSlash = toGRT('10')
        const tokensToReward = toGRT('10')
        const tx = staking
          .connect(slasher.signer)
          .slash(indexer.address, tokensToSlash, tokensToReward, fisherman.address)
        await expect(tx).revertedWith('indexer has no stakes')
      })
    })
  })

  context('> when staked', function () {
    beforeEach(async function () {
      await staking.connect(indexer.signer).stake(tokensToStake)
    })

    describe('hasStake', function () {
      it('should have stakes', async function () {
        expect(await staking.hasStake(indexer.address)).eq(true)
      })
    })

    describe('stake', function () {
      it('should allow re-staking', async function () {
        await shouldStake(tokensToStake)
      })
    })

    describe('unstake', function () {
      it('should unstake and lock tokens for thawing period', async function () {
        const tokensToUnstake = toGRT('2')
        const thawingPeriod = toBN(await staking.thawingPeriod())
        const currentBlock = await latestBlock()
        const until = currentBlock.add(thawingPeriod).add(toBN('1'))

        // Unstake
        const tx = staking.connect(indexer.signer).unstake(tokensToUnstake)
        await expect(tx)
          .emit(staking, 'StakeLocked')
          .withArgs(indexer.address, tokensToUnstake, until)
      })

      it('should unstake and lock tokens for (weighted avg) thawing period if repeated', async function () {
        const tokensToUnstake = toGRT('10')
        const thawingPeriod = toBN(await staking.thawingPeriod())

        // Unstake (1)
        const tx1 = await staking.connect(indexer.signer).unstake(tokensToUnstake)
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
        const tx2 = await staking.connect(indexer.signer).unstake(tokensToUnstake)
        const receipt2 = await tx2.wait()
        const event2: Event = receipt2.events.pop()
        const tokensLockedUntil2 = event2.args[2]
        expect(expectedLockedUntil).eq(tokensLockedUntil2)
      })

      it('reject unstake more than available tokens', async function () {
        const tokensOverCapacity = tokensToStake.add(toGRT('1'))
        const tx = staking.connect(indexer.signer).unstake(tokensOverCapacity)
        await expect(tx).revertedWith('not enough tokens available to unstake')
      })
    })

    describe('withdraw', function () {
      it('reject withdraw if no tokens available', async function () {
        const tx = staking.connect(indexer.signer).withdraw()
        await expect(tx).revertedWith('no tokens available to withdraw')
      })

      it('should withdraw if tokens available', async function () {
        // Unstake
        const tokensToUnstake = toGRT('10')
        const tx1 = await staking.connect(indexer.signer).unstake(tokensToUnstake)
        const receipt1 = await tx1.wait()
        const event1: Event = receipt1.events.pop()
        const tokensLockedUntil = event1.args['until']

        // Withdraw on locking period (should fail)
        const tx2 = staking.connect(indexer.signer).withdraw()
        await expect(tx2).revertedWith('no tokens available to withdraw')

        // Move forward
        await advanceBlockTo(tokensLockedUntil)

        // Withdraw after locking period (all good)
        const beforeBalance = await grt.balanceOf(indexer.address)
        const tx3 = staking.connect(indexer.signer).withdraw()
        await expect(tx3).emit(staking, 'StakeWithdrawn').withArgs(indexer.address, tokensToUnstake)
        const afterBalance = await grt.balanceOf(indexer.address)
        expect(afterBalance).eq(beforeBalance.add(tokensToUnstake))
      })
    })

    describe('slash', function () {
      // This function tests slashing behaviour under different conditions
      const shouldSlash = async function (
        indexer: Account,
        tokensToSlash: BigNumber,
        tokensToReward: BigNumber,
        fisherman: Account,
      ) {
        // Before
        const beforeTotalSupply = await grt.totalSupply()
        const beforeFishermanTokens = await grt.balanceOf(fisherman.address)
        const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

        // Slash indexer
        const tokensToBurn = tokensToSlash.sub(tokensToReward)
        const tx = staking
          .connect(slasher.signer)
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

      it('should slash indexer and give reward to beneficiary slash>reward', async function () {
        // Slash indexer
        const tokensToSlash = toGRT('100')
        const tokensToReward = toGRT('10')
        await shouldSlash(indexer, tokensToSlash, tokensToReward, fisherman)
      })

      it('should slash indexer and give reward to beneficiary slash=reward', async function () {
        // Slash indexer
        const tokensToSlash = toGRT('10')
        const tokensToReward = toGRT('10')
        await shouldSlash(indexer, tokensToSlash, tokensToReward, fisherman)
      })

      it('should slash indexer even when overallocated', async function () {
        // Initial stake
        const beforeTokensStaked = await staking.getIndexerStakedTokens(indexer.address)

        // Unstake partially, these tokens will be locked
        const tokensToUnstake = toGRT('10')
        await staking.connect(indexer.signer).unstake(tokensToUnstake)

        // Allocate indexer stake
        const tokensToAllocate = toGRT('70')
        await allocate(tokensToAllocate)

        // State pre-slashing
        // helpers.logStake(await staking.stakes(indexer.signer))
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
        // helpers.logStake(await staking.stakes(indexer.signer))
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

        const tx = staking.connect(indexer.signer).unstake(tokensToUnstake)
        await expect(tx).revertedWith('not enough tokens available to unstake')
      })

      it('reject to slash zero tokens', async function () {
        const tokensToSlash = toGRT('0')
        const tokensToReward = toGRT('0')
        const tx = staking
          .connect(slasher.signer)
          .slash(indexer.address, tokensToSlash, tokensToReward, me.address)
        await expect(tx).revertedWith('cannot slash zero tokens')
      })

      it('reject to slash indexer if caller is not slasher', async function () {
        const tokensToSlash = toGRT('100')
        const tokensToReward = toGRT('10')
        const tx = staking
          .connect(me.signer)
          .slash(indexer.address, tokensToSlash, tokensToReward, me.address)
        await expect(tx).revertedWith('Caller is not a Slasher')
      })

      it('reject to slash indexer if beneficiary is zero address', async function () {
        const tokensToSlash = toGRT('100')
        const tokensToReward = toGRT('10')
        const tx = staking
          .connect(slasher.signer)
          .slash(indexer.address, tokensToSlash, tokensToReward, AddressZero)
        await expect(tx).revertedWith('beneficiary must not be an empty address')
      })

      it('reject to slash indexer if reward is greater than slash amount', async function () {
        const tokensToSlash = toGRT('100')
        const tokensToReward = toGRT('200')
        const tx = staking
          .connect(slasher.signer)
          .slash(indexer.address, tokensToSlash, tokensToReward, fisherman.address)
        await expect(tx).revertedWith('reward cannot be higher than slashed amoun')
      })
    })
  })
})

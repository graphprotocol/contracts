import hre from 'hardhat'
import { expect } from 'chai'
import { BigNumber, constants, Event } from 'ethers'

import { GraphToken } from '../../../build/types/GraphToken'
import { IStaking } from '../../../build/types/IStaking'

import { NetworkFixture } from '../lib/fixtures'

import {
  deriveChannelKey,
  GraphNetworkContracts,
  helpers,
  randomHexBytes,
  toBN,
  toGRT,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const { AddressZero, MaxUint256 } = constants

function weightedAverage(
  valueA: BigNumber,
  valueB: BigNumber,
  periodA: BigNumber,
  periodB: BigNumber,
) {
  return periodA.mul(valueA).add(periodB.mul(valueB)).div(valueA.add(valueB))
}

describe('Staking:Stakes', () => {
  const graph = hre.graph()
  let me: SignerWithAddress
  let governor: SignerWithAddress
  let indexer: SignerWithAddress
  let slasher: SignerWithAddress
  let fisherman: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let grt: GraphToken
  let staking: IStaking

  // Test values
  const indexerTokens = toGRT('1000')
  const tokensToStake = toGRT('100')
  const subgraphDeploymentID = randomHexBytes()
  const channelKey = deriveChannelKey()
  const allocationID = channelKey.address
  const metadata = randomHexBytes(32)

  // Allocate with test values
  const allocate = async (tokens: BigNumber) => {
    return staking
      .connect(indexer)
      .allocateFrom(
        indexer.address,
        subgraphDeploymentID,
        tokens,
        allocationID,
        metadata,
        await channelKey.generateProof(indexer.address),
      )
  }

  // Stake and verify state change
  const shouldStake = async function (tokensToStake: BigNumber) {
    // Before state
    const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
    const beforeStakingBalance = await grt.balanceOf(staking.address)

    // Stake
    const tx = staking.connect(indexer).stake(tokensToStake)
    await expect(tx).emit(staking, 'StakeDeposited').withArgs(indexer.address, tokensToStake)

    // After state
    const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
    const afterStakingBalance = await grt.balanceOf(staking.address)

    // State updated
    expect(afterIndexerStake).eq(beforeIndexerStake.add(tokensToStake))
    expect(afterStakingBalance).eq(beforeStakingBalance.add(tokensToStake))
  }

  before(async function () {
    [me, indexer, slasher, fisherman] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())
    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    grt = contracts.GraphToken as GraphToken
    staking = contracts.Staking as IStaking

    // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
    await grt.connect(governor).mint(indexer.address, indexerTokens)
    await grt.connect(indexer).approve(staking.address, indexerTokens)

    await staking.connect(governor).setSlasher(slasher.address, true)
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
        const tx = staking.connect(indexer).stake(toGRT('0'))
        await expect(tx).revertedWith('!tokens')
      })

      it('reject stake less than minimum indexer stake', async function () {
        const amount = (await staking.minimumIndexerStake()).sub(toGRT('1'))
        const tx = staking.connect(indexer).stake(amount)
        await expect(tx).revertedWith('!minimumIndexerStake')
      })

      it('should stake tokens', async function () {
        await shouldStake(tokensToStake)
      })

      it('should stake tokens = minimumIndexerStake', async function () {
        await shouldStake(await staking.minimumIndexerStake())
      })
    })

    describe('unstake', function () {
      it('reject unstake tokens', async function () {
        const tokensToUnstake = toGRT('2')
        const tx = staking.connect(indexer).unstake(tokensToUnstake)
        await expect(tx).revertedWith('!stake')
      })
    })

    describe('slash', function () {
      it('reject slash indexer', async function () {
        const tokensToSlash = toGRT('10')
        const tokensToReward = toGRT('10')
        const tx = staking
          .connect(slasher)
          .slash(indexer.address, tokensToSlash, tokensToReward, fisherman.address)
        await expect(tx).revertedWith('!stake')
      })
    })
  })

  context('> when staked', function () {
    beforeEach(async function () {
      await staking.connect(indexer).stake(tokensToStake)
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

      it('reject to stake under the minimum indexer stake after unstake + slash', async function () {
        // Unstake (we get right on the minimum stake)
        const minimumIndexerStake = await staking.minimumIndexerStake()
        const tokensStaked = (await staking.stakes(indexer.address)).tokensStaked
        const tokensToGetOnMinimumStake = tokensStaked.sub(minimumIndexerStake)
        await staking.connect(indexer).unstake(tokensToGetOnMinimumStake)

        // Slash some indexer tokens to get under the water of the minimum indexer stake
        await staking
          .connect(slasher)
          .slash(indexer.address, toGRT('10'), toGRT(0), fisherman.address)

        // Stake should require to go over the minimum stake
        const tx = staking.connect(indexer).stake(toGRT('1'))
        await expect(tx).revertedWith('!minimumIndexerStake')
      })
    })

    describe('unstake', function () {
      it('should unstake and lock tokens for thawing period', async function () {
        const tokensToUnstake = toGRT('2')
        const thawingPeriod = toBN(await staking.thawingPeriod())
        const currentBlock = await helpers.latestBlock()
        const until = currentBlock + thawingPeriod.add(toBN('1')).toNumber()

        // Unstake
        const tx = staking.connect(indexer).unstake(tokensToUnstake)
        await expect(tx)
          .emit(staking, 'StakeLocked')
          .withArgs(indexer.address, tokensToUnstake, until)
      })

      it('should unstake and lock tokens for (weighted avg) thawing period if repeated', async function () {
        const tokensToUnstake = toGRT('10')
        const thawingPeriod = toBN(await staking.thawingPeriod())

        // Unstake (1)
        const tx1 = await staking.connect(indexer).unstake(tokensToUnstake)
        const receipt1 = await tx1.wait()
        const event1: Event = receipt1.events.pop()
        const tokensLockedUntil1 = event1.args['until']

        // Move forward before the tokens are unlocked for withdrawal
        await helpers.mineUpTo(tokensLockedUntil1.sub(5))

        // Calculate locking time for tokens taking into account the previous unstake request
        const currentBlock = await helpers.latestBlock()
        const lockingPeriod = weightedAverage(
          tokensToUnstake,
          tokensToUnstake,
          tokensLockedUntil1.sub(currentBlock),
          thawingPeriod,
        )
        const expectedLockedUntil = currentBlock + lockingPeriod.add(toBN('1')).toNumber()

        // Unstake (2)
        const tx2 = await staking.connect(indexer).unstake(tokensToUnstake)
        const receipt2 = await tx2.wait()

        // Verify events
        const event2: Event = receipt2.events.pop()
        expect(event2.args['until']).eq(expectedLockedUntil)

        // Verify state
        const afterIndexerStake = await staking.stakes(indexer.address)
        expect(afterIndexerStake.tokensLocked).eq(tokensToUnstake.mul(2)) // we unstaked two times
        expect(afterIndexerStake.tokensLockedUntil).eq(expectedLockedUntil)
      })

      it('should always increase the thawing period on subsequent unstakes', async function () {
        const tokensToUnstake = toGRT('10')
        const tokensToUnstakeSecondTime = toGRT('0.000001')

        // Unstake (1)
        const tx1 = await staking.connect(indexer).unstake(tokensToUnstake)
        const receipt1 = await tx1.wait()
        const event1: Event = receipt1.events.pop()
        const tokensLockedUntil1 = event1.args['until']

        // Move forward before the tokens are unlocked for withdrawal
        await helpers.mineUpTo(tokensLockedUntil1.sub(5))

        // Ensure at least 1 block is added (i.e. the weighted average rounds up)
        const expectedLockedUntil = tokensLockedUntil1.add(1)

        // Unstake (2)
        const tx2 = await staking.connect(indexer).unstake(tokensToUnstakeSecondTime)
        const receipt2 = await tx2.wait()

        // Verify events
        const event2: Event = receipt2.events.pop()
        expect(event2.args['until']).eq(expectedLockedUntil)

        // Verify state
        const afterIndexerStake = await staking.stakes(indexer.address)
        expect(afterIndexerStake.tokensLocked).eq(tokensToUnstake.add(tokensToUnstakeSecondTime)) // we unstaked two times
        expect(afterIndexerStake.tokensLockedUntil).eq(expectedLockedUntil)
      })

      it('should unstake and withdraw if some tokens are unthawed', async function () {
        const tokensToUnstake = toGRT('10')
        const thawingPeriod = toBN(await staking.thawingPeriod())

        const beforeIndexerBalance = await grt.balanceOf(indexer.address)

        // Unstake (1)
        const tx1 = await staking.connect(indexer).unstake(tokensToUnstake)
        const receipt1 = await tx1.wait()
        const event1: Event = receipt1.events.pop()
        const tokensLockedUntil1 = event1.args['until']

        // Move forward after the tokens are unlocked for withdrawal
        await helpers.mineUpTo(tokensLockedUntil1)

        // Calculate locking time for tokens taking into account some tokens are withdraweable
        const currentBlock = await helpers.latestBlock()
        const expectedLockedUntil = currentBlock + thawingPeriod.add(toBN('1')).toNumber()

        // Unstake (2)
        const tx2 = await staking.connect(indexer).unstake(tokensToUnstake)
        const receipt2 = await tx2.wait()

        // Verify events
        const unstakeEvent: Event = receipt2.events.pop()
        const withdrawEvent: Event = receipt2.events.pop()
        expect(unstakeEvent.args['until']).eq(expectedLockedUntil)
        expect(withdrawEvent.args['tokens']).eq(tokensToUnstake)

        // Verify state
        const afterIndexerStake = await staking.stakes(indexer.address)
        const afterIndexerBalance = await grt.balanceOf(indexer.address)
        expect(afterIndexerStake.tokensLocked).eq(tokensToUnstake)
        expect(afterIndexerStake.tokensLockedUntil).eq(expectedLockedUntil)
        expect(afterIndexerBalance).eq(beforeIndexerBalance.add(tokensToUnstake))
      })

      it('should unstake available tokens even if passed a higher amount', async function () {
        // Try to unstake a bit more than currently staked
        const tokensOverCapacity = tokensToStake.add(toGRT('1'))
        await staking.connect(indexer).unstake(tokensOverCapacity)

        // Check state
        const tokensLocked = (await staking.stakes(indexer.address)).tokensLocked
        expect(tokensLocked).eq(tokensToStake)
      })

      it('reject unstake zero tokens', async function () {
        const tx = staking.connect(indexer).unstake(toGRT('0'))
        await expect(tx).revertedWith('!stake-avail')
      })

      it('reject unstake under the minimum indexer stake', async function () {
        const minimumIndexerStake = await staking.minimumIndexerStake()
        const tokensStaked = (await staking.stakes(indexer.address)).tokensStaked
        const tokensToGetUnderMinimumStake = tokensStaked.sub(minimumIndexerStake).add(1)
        const tx = staking.connect(indexer).unstake(tokensToGetUnderMinimumStake)
        await expect(tx).revertedWith('!minimumIndexerStake')
      })

      it('reject unstake under the minimum indexer stake w/multiple unstake', async function () {
        const minimumIndexerStake = await staking.minimumIndexerStake()
        const tokensStaked = (await staking.stakes(indexer.address)).tokensStaked

        // First unstake (we get right on the minimum stake)
        const tokensToGetOnMinimumStake = tokensStaked.sub(minimumIndexerStake)
        await staking.connect(indexer).unstake(tokensToGetOnMinimumStake)

        // Second unstake, taking just one token out will make us under the minimum stake
        const tx = staking.connect(indexer).unstake(toGRT('1'))
        await expect(tx).revertedWith('!minimumIndexerStake')
      })

      it('should allow unstake of full amount', async function () {
        await staking.connect(indexer).unstake(tokensToStake)
        expect(await staking.getIndexerCapacity(indexer.address)).eq(0)
      })

      it('should allow unstake of full amount with no upper limits', async function () {
        // Use manual mining
        await helpers.setAutoMine(false)

        // Setup
        const newTokens = toGRT('2')
        const stakedTokens = await staking.getIndexerStakedTokens(indexer.address)
        const tokensToUnstake = stakedTokens.add(newTokens)

        // StakeTo & Unstake
        await staking.connect(indexer).stakeTo(indexer.address, newTokens)
        await staking.connect(indexer).unstake(MaxUint256)
        await helpers.mine()

        // Check state
        const tokensLocked = (await staking.stakes(indexer.address)).tokensLocked
        expect(tokensLocked).eq(tokensToUnstake)

        // Restore automine
        await helpers.setAutoMine(true)
      })
    })

    describe('withdraw', function () {
      it('reject withdraw if no tokens available', async function () {
        const tx = staking.connect(indexer).withdraw()
        await expect(tx).revertedWith('!tokens')
      })

      it('should withdraw if tokens available', async function () {
        // Unstake
        const tokensToUnstake = toGRT('10')
        const tx1 = await staking.connect(indexer).unstake(tokensToUnstake)
        const receipt1 = await tx1.wait()
        const event1: Event = receipt1.events.pop()
        const tokensLockedUntil = event1.args['until']

        // Withdraw on locking period (should fail)
        const tx2 = staking.connect(indexer).withdraw()
        await expect(tx2).revertedWith('!tokens')

        // Move forward
        await helpers.mineUpTo(tokensLockedUntil)

        // Withdraw after locking period (all good)
        const beforeBalance = await grt.balanceOf(indexer.address)
        const tx3 = staking.connect(indexer).withdraw()
        await expect(tx3).emit(staking, 'StakeWithdrawn').withArgs(indexer.address, tokensToUnstake)
        const afterBalance = await grt.balanceOf(indexer.address)
        expect(afterBalance).eq(beforeBalance.add(tokensToUnstake))
      })
    })

    describe('slash', function () {
      // This function tests slashing behaviour under different conditions
      const shouldSlash = async function (
        indexer: SignerWithAddress,
        tokensToSlash: BigNumber,
        tokensToReward: BigNumber,
        fisherman: SignerWithAddress,
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
        await expect(tx).revertedWith('!stake-avail')
      })

      it('reject to slash zero tokens', async function () {
        const tokensToSlash = toGRT('0')
        const tokensToReward = toGRT('0')
        const tx = staking
          .connect(slasher)
          .slash(indexer.address, tokensToSlash, tokensToReward, me.address)
        await expect(tx).revertedWith('!tokens')
      })

      it('reject to slash indexer if caller is not slasher', async function () {
        const tokensToSlash = toGRT('100')
        const tokensToReward = toGRT('10')
        const tx = staking
          .connect(me)
          .slash(indexer.address, tokensToSlash, tokensToReward, me.address)
        await expect(tx).revertedWith('!slasher')
      })

      it('reject to slash indexer if beneficiary is zero address', async function () {
        const tokensToSlash = toGRT('100')
        const tokensToReward = toGRT('10')
        const tx = staking
          .connect(slasher)
          .slash(indexer.address, tokensToSlash, tokensToReward, AddressZero)
        await expect(tx).revertedWith('!beneficiary')
      })

      it('reject to slash indexer if reward is greater than slash amount', async function () {
        const tokensToSlash = toGRT('100')
        const tokensToReward = toGRT('200')
        const tx = staking
          .connect(slasher)
          .slash(indexer.address, tokensToSlash, tokensToReward, fisherman.address)
        await expect(tx).revertedWith('rewards>slash')
      })
    })
  })
})

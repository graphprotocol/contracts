import { expect } from 'chai'
import { constants, BigNumber } from 'ethers'

import { EpochManager } from '../../build/types/EpochManager'
import { GraphToken } from '../../build/types/GraphToken'
import { Staking } from '../../build/types/Staking'

import { NetworkFixture } from '../lib/fixtures'
import {
  advanceToNextEpoch,
  deriveChannelKey,
  getAccounts,
  latestBlock,
  randomHexBytes,
  toGRT,
  toBN,
  Account,
  advanceBlock,
} from '../lib/testHelpers'

const { AddressZero, HashZero } = constants
const MAX_PPM = toBN('1000000')
const percentageOf = (ppm: BigNumber, value): BigNumber => value.sub(ppm.mul(value).div(MAX_PPM))

describe('Staking::Delegation', () => {
  let me: Account
  let delegator: Account
  let delegator2: Account
  let governor: Account
  let indexer: Account
  let indexer2: Account
  let assetHolder: Account

  let fixture: NetworkFixture

  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

  // Test values
  const poi = randomHexBytes()
  const metadata = HashZero

  async function shouldDelegate(sender: Account, tokens: BigNumber) {
    // Before state
    const beforeTotalSupply = await grt.totalSupply()
    const beforePool = await staking.delegationPools(indexer.address)
    const beforeDelegation = await staking.getDelegation(indexer.address, sender.address)
    const beforeShares = beforeDelegation.shares
    const beforeTokens = beforePool.shares.gt(0)
      ? beforeShares.mul(beforePool.tokens).div(beforePool.shares)
      : toBN(0)

    // Get current delegation tax percentage for deposits
    const delegationTaxPercentage = BigNumber.from(await staking.delegationTaxPercentage())
    const delegationTax = delegationTaxPercentage.mul(tokens).div(MAX_PPM)
    const delegatedTokens = tokens.sub(delegationTax)

    // Calculate shares to receive
    const shares = beforePool.tokens.eq(toBN('0'))
      ? delegatedTokens
      : delegatedTokens.mul(beforePool.tokens).div(beforePool.shares)

    // Delegate
    const tx = staking.connect(sender.signer).delegate(indexer.address, tokens)
    await expect(tx)
      .emit(staking, 'StakeDelegated')
      .withArgs(indexer.address, sender.address, delegatedTokens, shares)

    // After state
    const afterTotalSupply = await grt.totalSupply()
    const afterPool = await staking.delegationPools(indexer.address)
    const afterDelegation = await staking.getDelegation(indexer.address, sender.address)
    const afterShares = afterDelegation.shares
    const afterTokens = afterPool.shares.gt(0)
      ? afterShares.mul(afterPool.tokens).div(afterPool.shares)
      : toBN(0)

    // State updated
    expect(afterPool.tokens).eq(beforePool.tokens.add(delegatedTokens))
    expect(afterPool.shares).eq(beforePool.shares.add(shares))
    expect(afterShares).eq(beforeShares.add(shares))
    expect(afterTokens).eq(beforeTokens.add(delegatedTokens))
    expect(afterTotalSupply).eq(beforeTotalSupply.sub(delegationTax))
  }

  async function shouldUndelegate(sender: Account, shares: BigNumber) {
    // Before state
    const beforePool = await staking.delegationPools(indexer.address)
    const beforeDelegation = await staking.getDelegation(indexer.address, sender.address)
    const beforeShares = beforeDelegation.shares
    const beforeTokens = beforePool.shares.gt(0)
      ? beforeShares.mul(beforePool.tokens).div(beforePool.shares)
      : toBN(0)
    const beforeDelegatorBalance = await grt.balanceOf(sender.address)
    const tokensToWithdraw = await staking.getWithdraweableDelegatedTokens(beforeDelegation)

    // Calculate tokens to receive
    const tokens = shares.mul(beforePool.shares).div(beforePool.tokens)

    // Undelegate
    const currentEpoch = await epochManager.currentEpoch()
    const delegationUnbondingPeriod = await staking.delegationUnbondingPeriod()
    const tokensLockedUntil = currentEpoch.add(delegationUnbondingPeriod)

    const tx = staking.connect(sender.signer).undelegate(indexer.address, shares)
    await expect(tx)
      .emit(staking, 'StakeDelegatedLocked')
      .withArgs(indexer.address, sender.address, tokens, shares, tokensLockedUntil)

    // After state
    const afterPool = await staking.delegationPools(indexer.address)
    const afterDelegation = await staking.getDelegation(indexer.address, sender.address)
    const afterShares = afterDelegation.shares
    const afterTokens = afterPool.shares.gt(0)
      ? afterShares.mul(afterPool.tokens).div(afterPool.shares)
      : toBN(0)
    const afterDelegatorBalance = await grt.balanceOf(sender.address)

    // State updated
    expect(afterPool.tokens).eq(beforePool.tokens.sub(tokens))
    expect(afterPool.shares).eq(beforePool.shares.sub(shares))
    expect(afterShares).eq(beforeShares.sub(shares))
    expect(afterTokens).eq(beforeTokens.sub(tokens))

    // Undelegated funds must be put on lock
    expect(afterDelegation.tokensLocked).eq(
      beforeDelegation.tokensLocked.add(tokens).sub(tokensToWithdraw),
    )
    expect(afterDelegation.tokensLockedUntil).eq(tokensLockedUntil)
    // Delegator see balance increased only if there were tokens to withdraw
    expect(afterDelegatorBalance).eq(beforeDelegatorBalance.add(tokensToWithdraw))
  }

  async function shouldWithdrawDelegated(sender: Account, redelegateTo: string, tokens: BigNumber) {
    // Before state
    const beforePool = await staking.delegationPools(indexer2.address)
    const beforeDelegation = await staking.getDelegation(indexer2.address, sender.address)
    const beforeShares = beforeDelegation.shares
    const beforeTokens = beforePool.shares.gt(0)
      ? beforeShares.mul(beforePool.tokens).div(beforePool.shares)
      : toBN(0)
    const beforeBalance = await grt.balanceOf(delegator.address)

    // Calculate shares to receive
    const shares = beforePool.tokens.eq(toBN('0'))
      ? tokens
      : tokens.mul(beforePool.tokens).div(beforePool.shares)

    // Withdraw
    const tx = staking.connect(delegator.signer).withdrawDelegated(indexer.address, redelegateTo)
    await expect(tx)
      .emit(staking, 'StakeDelegatedWithdrawn')
      .withArgs(indexer.address, delegator.address, tokens)

    // After state
    const afterPool = await staking.delegationPools(indexer2.address)
    const afterDelegation = await staking.getDelegation(indexer2.address, sender.address)
    const afterShares = afterDelegation.shares
    const afterTokens = afterPool.shares.gt(0)
      ? afterShares.mul(afterPool.tokens).div(afterPool.shares)
      : toBN(0)
    const afterBalance = await grt.balanceOf(delegator.address)

    // State updated
    expect(afterDelegation.tokensLocked).eq(toGRT('0'))
    expect(afterDelegation.tokensLockedUntil).eq(toBN('0'))
    // Redelegation vs transfer
    if (redelegateTo === AddressZero) {
      expect(afterBalance).eq(beforeBalance.add(tokens))
    } else {
      expect(afterBalance).eq(beforeBalance)
      expect(afterPool.tokens).eq(beforePool.tokens.add(tokens))
      expect(afterPool.shares).eq(beforePool.shares.add(shares))
      expect(afterShares).eq(beforeShares.add(shares))
      expect(afterTokens).eq(beforeTokens.add(tokens))
    }
  }

  before(async function () {
    ;[me, delegator, delegator2, governor, indexer, indexer2, assetHolder] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ epochManager, grt, staking } = await fixture.load(governor.signer))

    // Distribute test funds
    for (const wallet of [delegator, delegator2]) {
      await grt.connect(governor.signer).mint(wallet.address, toGRT('10000000000000000000'))
      await grt.connect(wallet.signer).approve(staking.address, toGRT('10000000000000000000'))
    }

    // Distribute test funds
    for (const wallet of [me, indexer, indexer2, assetHolder]) {
      await grt.connect(governor.signer).mint(wallet.address, toGRT('1000000'))
      await grt.connect(wallet.signer).approve(staking.address, toGRT('1000000'))
    }

    // Allow the asset holder
    await staking.connect(governor.signer).setAssetHolder(assetHolder.address, true)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('configuration', function () {
    describe('delegationRatio', function () {
      const delegationRatio = 5

      it('should set `delegationRatio`', async function () {
        await staking.connect(governor.signer).setDelegationRatio(delegationRatio)
        expect(await staking.delegationRatio()).eq(delegationRatio)
      })

      it('reject set `delegationRatio` if not allowed', async function () {
        const tx = staking.connect(me.signer).setDelegationRatio(delegationRatio)
        await expect(tx).revertedWith('Caller must be Controller governor')
      })
    })

    describe('delegationParametersCooldown', function () {
      const cooldown = 5

      it('should set `delegationParametersCooldown`', async function () {
        await staking.connect(governor.signer).setDelegationParametersCooldown(cooldown)
        expect(await staking.delegationParametersCooldown()).eq(cooldown)
      })

      it('reject set `delegationParametersCooldown` if not allowed', async function () {
        const tx = staking.connect(me.signer).setDelegationParametersCooldown(cooldown)
        await expect(tx).revertedWith('Caller must be Controller governor')
      })
    })

    describe('delegationTaxPercentage', function () {
      it('should set `delegationTaxPercentage`', async function () {
        for (const newValue of [toBN('0'), toBN('5'), MAX_PPM]) {
          await staking.connect(governor.signer).setDelegationTaxPercentage(newValue)
          expect(await staking.delegationTaxPercentage()).eq(newValue)
        }
      })

      it('reject set `delegationTaxPercentage` if out of bounds', async function () {
        const newValue = MAX_PPM.add(toBN('1'))
        const tx = staking.connect(governor.signer).setDelegationTaxPercentage(newValue)
        await expect(tx).revertedWith('>percentage')
      })

      it('reject set `delegationTaxPercentage` if not allowed', async function () {
        const tx = staking.connect(me.signer).setDelegationTaxPercentage(50)
        await expect(tx).revertedWith('Caller must be Controller governor')
      })
    })

    describe('delegationParameters', function () {
      const indexingRewardCut = toBN('50000')
      const queryFeeCut = toBN('80000')
      const cooldownBlocks = 5

      it('reject to set if under cooldown period', async function () {
        // Set parameters
        await staking
          .connect(indexer.signer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)

        // Try to set before cooldown period passed
        const tx = staking
          .connect(indexer.signer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)
        await expect(tx).revertedWith('!cooldown')
      })

      it('reject to set if cooldown below the global configuration', async function () {
        // Set global cooldown parameter
        await staking.connect(governor.signer).setDelegationParametersCooldown(cooldownBlocks)

        // Try to set delegation cooldown below global cooldown parameter
        const tx = staking
          .connect(indexer.signer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks - 1)
        await expect(tx).revertedWith('<cooldown')
      })

      it('reject to set parameters out of bound', async function () {
        // Indexing reward out of bounds
        const tx1 = staking
          .connect(indexer.signer)
          .setDelegationParameters(MAX_PPM.add('1'), queryFeeCut, cooldownBlocks)
        await expect(tx1).revertedWith('>indexingRewardCut')

        // Query fee out of bounds
        const tx2 = staking
          .connect(indexer.signer)
          .setDelegationParameters(indexingRewardCut, MAX_PPM.add('1'), cooldownBlocks)
        await expect(tx2).revertedWith('>queryFeeCut')
      })

      it('should set parameters', async function () {
        // Set parameters
        const tx = staking
          .connect(indexer.signer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)
        await expect(tx)
          .emit(staking, 'DelegationParametersUpdated')
          .withArgs(indexer.address, indexingRewardCut, queryFeeCut, cooldownBlocks)

        // State updated
        const params = await staking.delegationPools(indexer.address)
        expect(params.indexingRewardCut).eq(indexingRewardCut)
        expect(params.queryFeeCut).eq(queryFeeCut)
        expect(params.cooldownBlocks).eq(cooldownBlocks)
        expect(params.updatedAtBlock).eq(await latestBlock())
      })

      it('should init delegation parameters on first stake', async function () {
        // Before
        const beforeParams = await staking.delegationPools(indexer.address)
        expect(beforeParams.indexingRewardCut).eq(0)
        expect(beforeParams.queryFeeCut).eq(0)
        expect(beforeParams.cooldownBlocks).eq(0)
        expect(beforeParams.updatedAtBlock).eq(0)

        // Indexer stake tokens
        const tx = staking.connect(indexer.signer).stake(toGRT('200'))
        await expect(tx)
          .emit(staking, 'DelegationParametersUpdated')
          .withArgs(indexer.address, MAX_PPM, MAX_PPM, 0)

        // State updated
        const afterParams = await staking.delegationPools(indexer.address)
        expect(afterParams.indexingRewardCut).eq(MAX_PPM)
        expect(afterParams.queryFeeCut).eq(MAX_PPM)
        expect(afterParams.cooldownBlocks).eq(0)
        expect(afterParams.updatedAtBlock).eq(await latestBlock())
      })

      it('should init delegation parameters on first stake using stakeTo()', async function () {
        // Before
        const beforeParams = await staking.delegationPools(indexer.address)
        expect(beforeParams.indexingRewardCut).eq(0)
        expect(beforeParams.queryFeeCut).eq(0)
        expect(beforeParams.cooldownBlocks).eq(0)
        expect(beforeParams.updatedAtBlock).eq(0)

        // Indexer stake tokens
        const tx = staking.connect(me.signer).stakeTo(indexer.address, toGRT('200'))
        await expect(tx)
          .emit(staking, 'DelegationParametersUpdated')
          .withArgs(indexer.address, MAX_PPM, MAX_PPM, 0)

        // State updated
        const afterParams = await staking.delegationPools(indexer.address)
        expect(afterParams.indexingRewardCut).eq(MAX_PPM)
        expect(afterParams.queryFeeCut).eq(MAX_PPM)
        expect(afterParams.cooldownBlocks).eq(0)
        expect(afterParams.updatedAtBlock).eq(await latestBlock())
      })
    })
  })

  describe('lifecycle', function () {
    beforeEach(async function () {
      // Stake some funds as indexer
      await staking.connect(indexer.signer).stake(toGRT('1000'))
    })

    describe('delegate', function () {
      it('reject delegate with zero tokens', async function () {
        const tokensToDelegate = toGRT('0')
        const tx = staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        await expect(tx).revertedWith('!tokens')
      })

      it('reject delegate to empty address', async function () {
        const tokensToDelegate = toGRT('100')
        const tx = staking.connect(delegator.signer).delegate(AddressZero, tokensToDelegate)
        await expect(tx).revertedWith('!indexer')
      })

      it('reject delegate to non-staked indexer', async function () {
        const tokensToDelegate = toGRT('100')
        const tx = staking.connect(delegator.signer).delegate(me.address, tokensToDelegate)
        await expect(tx).revertedWith('!stake')
      })

      it('should delegate tokens and account shares proportionally', async function () {
        // Multiple delegations should work
        await shouldDelegate(delegator, toGRT('1234'))
        await shouldDelegate(delegator, toGRT('100'))
        await shouldDelegate(delegator, toGRT('50'))
        await shouldDelegate(delegator, toGRT('25'))
        await shouldDelegate(delegator, toGRT('10'))
        await shouldDelegate(delegator, toGRT('1'))

        // Delegation by other delegator
        await shouldDelegate(delegator2, toGRT('5000'))
      })

      it('should delegate a high amount of tokens', async function () {
        await shouldDelegate(delegator, toGRT('100'))
        await shouldDelegate(delegator, toGRT('1000000000000000000'))
      })

      describe('delegation tax', function () {
        it('should delegate and burn delegation deposit tax (0.0001%)', async function () {
          await staking.setDelegationTaxPercentage(1)
          await shouldDelegate(delegator, toGRT('10000000'))
        })

        it('should delegate and burn delegation deposit tax (1%)', async function () {
          await staking.setDelegationTaxPercentage(10000)
          await shouldDelegate(delegator, toGRT('10000000'))
        })

        it('reject delegate with delegation deposit tax (100%)', async function () {
          await staking.setDelegationTaxPercentage(1000000)
          const tx = staking.connect(delegator.signer).delegate(indexer.address, toGRT('10000000'))
          await expect(tx).revertedWith('!shares')
        })
      })
    })

    describe('undelegate', function () {
      it('reject to undelegate zero shares', async function () {
        const tx = staking.connect(delegator.signer).undelegate(indexer.address, toGRT('0'))
        await expect(tx).revertedWith('!shares')
      })

      it('reject to undelegate more shares than owned', async function () {
        const tx = staking.connect(delegator.signer).undelegate(indexer.address, toGRT('100'))
        await expect(tx).revertedWith('!shares-avail')
      })

      it('should exchange delegation pool shares for tokens', async function () {
        const tokens = toGRT('100')

        // Have two parties that delegated tokens to the same indexer
        await shouldDelegate(delegator, tokens)
        await shouldDelegate(delegator2, tokens)

        // Delegate half of the delegated funds
        await shouldUndelegate(delegator, tokens.div(toBN('2')))
      })

      it('should undelegate properly when multiple delegations', async function () {
        this.timeout(60000) // increase timeout for test runner

        // Use long enough epochs to avoid jumping to the next epoch involuntarily on our test
        await epochManager.setEpochLength(toBN((60 * 60) / 15))

        await shouldDelegate(delegator, toGRT('1234'))
        await shouldDelegate(delegator, toGRT('100'))
        await shouldDelegate(delegator, toGRT('50'))
        await shouldDelegate(delegator2, toGRT('50'))

        await shouldUndelegate(delegator, toGRT('1'))
        await shouldUndelegate(delegator2, toGRT('50'))
        await advanceToNextEpoch(epochManager)
        await shouldUndelegate(delegator, toGRT('25'))
      })

      it('should undelegate and withdraw freed tokens from unbonding period', async function () {
        await staking.setDelegationUnbondingPeriod('2')
        await shouldDelegate(delegator, toGRT('100'))
        await shouldUndelegate(delegator, toGRT('50'))
        await advanceBlock()
        await advanceToNextEpoch(epochManager) // epoch 1
        await advanceToNextEpoch(epochManager) // epoch 2
        await shouldUndelegate(delegator, toGRT('10'))
      })
    })

    describe('withdraw', function () {
      it('reject withdraw if no funds available', async function () {
        const tx = staking.connect(delegator.signer).withdrawDelegated(indexer.address, AddressZero)
        await expect(tx).revertedWith('!tokens')
      })

      it('reject withdraw before unbonding period', async function () {
        await staking.setDelegationUnbondingPeriod('2')
        await shouldDelegate(delegator, toGRT('1000'))
        await shouldUndelegate(delegator, toGRT('100'))

        // Withdraw
        const tx = staking.connect(delegator.signer).withdrawDelegated(indexer.address, AddressZero)
        await expect(tx).revertedWith('!tokens')
      })

      it('should withdraw after waiting an unbonding period', async function () {
        const tokensToWithdraw = toGRT('100')

        // Setup
        await staking.setDelegationUnbondingPeriod('2')
        await shouldDelegate(delegator, toGRT('1000'))
        await shouldUndelegate(delegator, tokensToWithdraw)
        await advanceToNextEpoch(epochManager) // epoch 1
        await advanceToNextEpoch(epochManager) // epoch 2

        // Withdraw
        await shouldWithdrawDelegated(delegator, AddressZero, tokensToWithdraw)
      })

      it('should withdraw after waiting an unbonding period (with redelegation)', async function () {
        const tokensToWithdraw = toGRT('100')

        // Setup
        await staking.setDelegationUnbondingPeriod('2')
        await shouldDelegate(delegator, toGRT('1000'))
        await shouldUndelegate(delegator, tokensToWithdraw)
        await advanceToNextEpoch(epochManager) // epoch 1
        await advanceToNextEpoch(epochManager) // epoch 2

        // We stake on indexer2 so the delegator is able to re-delegate to it
        // if we didn't do it, it will revert because of indexer2 not havings stake
        await staking.connect(indexer2.signer).stake(toGRT('1000'))
        // Withdraw
        await shouldWithdrawDelegated(delegator, indexer2.address, tokensToWithdraw)
      })
    })
  })

  describe('use of delegated funds', function () {
    // Test values
    const tokensToStake = toGRT('200')
    const tokensToAllocate = toGRT('2000')
    const tokensToCollect = toGRT('500')
    const tokensToDelegate = toGRT('1800')
    const subgraphDeploymentID = randomHexBytes()
    const channelKey = deriveChannelKey()
    const allocationID = channelKey.address

    const setupAllocation = async (tokens: BigNumber) => {
      return staking
        .connect(indexer.signer)
        .allocate(
          subgraphDeploymentID,
          tokens,
          allocationID,
          metadata,
          await channelKey.generateProof(indexer.address),
        )
    }

    beforeEach(async function () {
      // Indexer stake tokens
      await staking.connect(indexer.signer).stake(tokensToStake)
    })

    it('revert allocate when capacity is not enough', async function () {
      // 1:2 delegation capacity
      await staking.connect(governor.signer).setDelegationRatio(2)

      // Delegate
      await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

      // Staked: 200
      // Delegated: 1800
      // Capacity: 200 + min(200*2, 1800) = 600
      const tx = setupAllocation(tokensToAllocate)
      await expect(tx).revertedWith('!capacity')
    })

    it('should allocate using full delegation capacity', async function () {
      // 1:10 delegation capacity
      await staking.connect(governor.signer).setDelegationRatio(10)

      // Delegate
      await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

      // Staked: 200
      // Delegated: 1800
      // Capacity: 200 + min(200*10, 1800) = 2000
      await setupAllocation(tokensToAllocate)

      // State updated
      const alloc = await staking.getAllocation(allocationID)
      expect(alloc.tokens).eq(tokensToAllocate)
    })

    it('should account delegation for indexer capacity properly', async function () {
      // 1:10 delegation capacity
      await staking.connect(governor.signer).setDelegationRatio(10)

      // Delegate
      await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

      // If we unstake all, the indexer capacity should go to zero
      // Should not be able to use delegated tokens
      await staking.connect(indexer.signer).unstake(tokensToStake)
      expect(await staking.getIndexerCapacity(indexer.address)).eq(0)
    })

    it('should send delegation cut of query fees to delegation pool', async function () {
      // 1:10 delegation capacity
      await staking.connect(governor.signer).setDelegationRatio(10)

      // Set delegation rules for the indexer
      const indexingRewardCut = toBN('800000') // indexer keep 80%
      const queryFeeCut = toBN('950000') // indexer keeps 95%
      const cooldownBlocks = 5
      await staking
        .connect(indexer.signer)
        .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)

      // Delegate
      await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

      // Prepare allocation
      await setupAllocation(tokensToAllocate)

      // Collect some funds
      await staking.connect(assetHolder.signer).collect(tokensToCollect, allocationID)

      // Advance blocks to get the channel in epoch where it can be closed
      await advanceToNextEpoch(epochManager)

      // Close allocation
      await staking.connect(indexer.signer).closeAllocation(allocationID, poi)

      // Advance blocks to get the channel in epoch where it can be claimed
      await advanceToNextEpoch(epochManager)

      // Delegation pool before allocation closed
      const beforeDelegationPool = await staking.delegationPools(indexer.address)

      // Calculate tokens to claim and expected delegation fees
      const beforeAlloc = await staking.getAllocation(allocationID)
      const delegationFees = percentageOf(queryFeeCut, beforeAlloc.collectedFees)
      const tokensToClaim = beforeAlloc.collectedFees.sub(delegationFees)

      // Claim from rebate pool
      const currentEpoch = await epochManager.currentEpoch()
      const tx = staking.connect(indexer.signer).claim(allocationID, true)
      await expect(tx)
        .emit(staking, 'RebateClaimed')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          allocationID,
          currentEpoch,
          beforeAlloc.closedAtEpoch,
          tokensToClaim,
          toBN('0'),
          delegationFees,
        )

      // State updated
      const afterDelegationPool = await staking.delegationPools(indexer.address)
      expect(afterDelegationPool.tokens).eq(beforeDelegationPool.tokens.add(delegationFees))
    })

    it('revert if it cannot assign the smallest amount of shares', async function () {
      // Init the delegation pool
      await shouldDelegate(delegator, tokensToDelegate)

      // Collect funds thru full allocation cycle
      await staking.connect(governor.signer).setDelegationRatio(10)
      await staking.connect(indexer.signer).setDelegationParameters(0, 0, 0)
      await setupAllocation(tokensToAllocate)
      await staking.connect(assetHolder.signer).collect(tokensToCollect, allocationID)
      await advanceToNextEpoch(epochManager)
      await staking.connect(indexer.signer).closeAllocation(allocationID, poi)
      await advanceToNextEpoch(epochManager)
      await staking.connect(indexer.signer).claim(allocationID, true)

      // Delegate with such small amount of tokens (1 wei) that we do not have enough precision
      // to even assign 1 wei of shares
      const tx = staking.connect(delegator.signer).delegate(indexer.address, toBN(1))
      await expect(tx).revertedWith('!shares')
    })
  })
})

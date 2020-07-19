import { expect } from 'chai'
import { constants, BigNumber } from 'ethers'

import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'
import {
  advanceToNextEpoch,
  getAccounts,
  latestBlock,
  randomHexBytes,
  toGRT,
  toBN,
  Account,
} from '../lib/testHelpers'

const { AddressZero } = constants
const MAX_PPM = toBN('1000000')
const percentageOf = (ppm: BigNumber, value): BigNumber => value.sub(ppm.mul(value).div(MAX_PPM))

describe('Staking::Delegation', () => {
  let me: Account
  let delegator: Account
  let delegator2: Account
  let governor: Account
  let indexer: Account
  let indexer2: Account
  let channelProxy: Account

  let fixture: NetworkFixture

  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

  async function shouldDelegate(sender: Account, tokens: BigNumber) {
    // Before state
    const beforePool = await staking.delegationPools(indexer.address)
    const beforeShares = await staking.getDelegationShares(indexer.address, sender.address)
    const beforeTokens = await staking.getDelegationTokens(indexer.address, sender.address)

    // Calculate shares to receive
    const shares = beforePool.tokens.eq(toBN('0'))
      ? tokens
      : tokens.mul(beforePool.tokens).div(beforePool.shares)

    // Delegate
    const tx = staking.connect(sender.signer).delegate(indexer.address, tokens)
    await expect(tx)
      .emit(staking, 'StakeDelegated')
      .withArgs(indexer.address, sender.address, tokens, shares)

    // After state
    const afterPool = await staking.delegationPools(indexer.address)
    const afterShares = await staking.getDelegationShares(indexer.address, sender.address)
    const afterTokens = await staking.getDelegationTokens(indexer.address, sender.address)

    // State updated
    expect(afterPool.tokens).eq(beforePool.tokens.add(tokens))
    expect(afterPool.shares).eq(beforePool.shares.add(shares))
    expect(afterShares).eq(beforeShares.add(shares))
    expect(afterTokens).eq(beforeTokens.add(tokens))
  }

  async function shouldUndelegate(sender: Account, shares: BigNumber) {
    // Before state
    const beforePool = await staking.delegationPools(indexer.address)
    const beforeDelegation = await staking.getDelegation(indexer.address, sender.address)
    const beforeShares = await staking.getDelegationShares(indexer.address, sender.address)
    const beforeTokens = await staking.getDelegationTokens(indexer.address, sender.address)
    const beforeDelegatorBalance = await grt.balanceOf(sender.address)

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
    const afterShares = await staking.getDelegationShares(indexer.address, sender.address)
    const afterTokens = await staking.getDelegationTokens(indexer.address, sender.address)
    const afterDelegatorBalance = await grt.balanceOf(sender.address)

    // State updated
    expect(afterPool.tokens).eq(beforePool.tokens.sub(tokens))
    expect(afterPool.shares).eq(beforePool.shares.sub(shares))
    expect(afterShares).eq(beforeShares.sub(shares))
    expect(afterTokens).eq(beforeTokens.sub(tokens))
    // Undelegated funds must be put on lock
    expect(afterDelegation.tokensLocked).eq(beforeDelegation.tokensLocked.add(tokens))
    expect(afterDelegation.tokensLockedUntil).eq(tokensLockedUntil)
    // No funds must be transferred to the delegator
    expect(afterDelegatorBalance).eq(beforeDelegatorBalance)
  }

  async function shouldWithdrawDelegated(sender: Account, redelegateTo: string, tokens: BigNumber) {
    // Before state
    const beforePool = await staking.delegationPools(indexer2.address)
    const beforeShares = await staking.getDelegationShares(indexer2.address, sender.address)
    const beforeTokens = await staking.getDelegationTokens(indexer2.address, sender.address)
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
    const afterShares = await staking.getDelegationShares(indexer2.address, sender.address)
    const afterTokens = await staking.getDelegationTokens(indexer2.address, sender.address)
    const afterDelegation = await staking.getDelegation(indexer.address, delegator.address)
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
    ;[me, delegator, delegator2, governor, indexer, indexer2, channelProxy] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ epochManager, grt, staking } = await fixture.load(governor.signer))

    // Distribute test funds
    for (const wallet of [delegator, delegator2]) {
      await grt.connect(governor.signer).mint(wallet.address, toGRT('10000000000000000000'))
      await grt.connect(wallet.signer).approve(staking.address, toGRT('10000000000000000000'))
    }

    // Distribute test funds
    for (const wallet of [me, indexer, channelProxy]) {
      await grt.connect(governor.signer).mint(wallet.address, toGRT('1000000'))
      await grt.connect(wallet.signer).approve(staking.address, toGRT('1000000'))
    }
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('configuration', function () {
    describe('delegationCapacity', function () {
      const delegationCapacity = 5

      it('should set `delegationCapacity`', async function () {
        await staking.connect(governor.signer).setDelegationCapacity(delegationCapacity)
        expect(await staking.delegationCapacity()).eq(delegationCapacity)
      })

      it('reject set `delegationCapacity` if not allowed', async function () {
        const tx = staking.connect(me.signer).setDelegationCapacity(delegationCapacity)
        await expect(tx).revertedWith('Only Governor can call')
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
        await expect(tx).revertedWith('Only Governor can call')
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
        await expect(tx).revertedWith(
          'Delegation: must expire cooldown period to update parameters',
        )
      })

      it('reject to set if cooldown below the global configuration', async function () {
        // Set global cooldown parameter
        await staking.connect(governor.signer).setDelegationParametersCooldown(cooldownBlocks)

        // Try to set delegation cooldown below global cooldown parameter
        const tx = staking
          .connect(indexer.signer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks - 1)
        await expect(tx).revertedWith('Delegation: cooldown cannot be below minimum')
      })

      it('reject to set parameters out of bound', async function () {
        // Indexing reward out of bounds
        const tx1 = staking
          .connect(indexer.signer)
          .setDelegationParameters(MAX_PPM.add('1'), queryFeeCut, cooldownBlocks)
        await expect(tx1).revertedWith(
          'Delegation: IndexingRewardCut must be below or equal to MAX_PPM',
        )

        // Query fee out of bounds
        const tx2 = staking
          .connect(indexer.signer)
          .setDelegationParameters(indexingRewardCut, MAX_PPM.add('1'), cooldownBlocks)
        await expect(tx2).revertedWith('Delegation: QueryFeeCut must be below or equal to MAX_PPM')
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
    })
  })

  describe('lifecycle', function () {
    describe('delegate', function () {
      it('reject to delegate zero tokens', async function () {
        const tokensToDelegate = toGRT('0')
        const tx = staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        await expect(tx).revertedWith('Delegation: cannot delegate zero tokens')
      })

      it('reject to delegate to empty address', async function () {
        const tokensToDelegate = toGRT('100')
        const tx = staking.connect(delegator.signer).delegate(AddressZero, tokensToDelegate)
        await expect(tx).revertedWith('Delegation: cannot delegate to empty address')
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

      it('should delegate a high number of tokens', async function () {
        await shouldDelegate(delegator, toGRT('100'))
        await shouldDelegate(delegator, toGRT('1000000000000000000'))
      })
    })

    describe('undelegate', function () {
      it('reject to undelegate zero shares', async function () {
        const tx = staking.connect(delegator.signer).undelegate(indexer.address, toGRT('0'))
        await expect(tx).revertedWith('Delegation: cannot undelegate zero shares')
      })

      it('reject to undelegate more shares than owned', async function () {
        const tx = staking.connect(delegator.signer).undelegate(indexer.address, toGRT('100'))
        await expect(tx).revertedWith('Delegation: delegator does not have enough shares')
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
        await shouldDelegate(delegator, toGRT('1234'))
        await shouldDelegate(delegator, toGRT('100'))
        await shouldDelegate(delegator, toGRT('50'))
        await shouldDelegate(delegator2, toGRT('50'))

        await shouldUndelegate(delegator, toGRT('1'))
        await shouldUndelegate(delegator2, toGRT('50'))
        await advanceToNextEpoch(epochManager)
        await shouldUndelegate(delegator, toGRT('25'))
      })
    })

    describe('withdraw', function () {
      it('reject withdraw if no funds available', async function () {
        const tx = staking.connect(delegator.signer).withdrawDelegated(indexer.address, AddressZero)
        await expect(tx).revertedWith('Delegation: no tokens available to withdraw')
      })

      it('reject withdraw before unbonding period', async function () {
        await staking.setDelegationUnbondingPeriod('2')
        await shouldDelegate(delegator, toGRT('1000'))
        await shouldUndelegate(delegator, toGRT('100'))

        // Withdraw
        const tx = staking.connect(delegator.signer).withdrawDelegated(indexer.address, AddressZero)
        await expect(tx).revertedWith('Delegation: no tokens available to withdraw')
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
    const channelID = '0x6367E9dD7641e0fF221740b57B8C730031d72530'
    const channelPubKey =
      '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'

    const setupAllocation = async (tokens: BigNumber) => {
      return staking
        .connect(indexer.signer)
        .allocate(subgraphDeploymentID, tokens, channelPubKey, channelProxy.address, toGRT('0.01'))
    }

    beforeEach(async function () {
      // Indexer stake tokens
      await staking.connect(indexer.signer).stake(tokensToStake)
    })

    it('revert allocate when capacity is not enough', async function () {
      // 1:2 delegation capacity
      await staking.connect(governor.signer).setDelegationCapacity(2)

      // Delegate
      await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

      // Staked: 200
      // Delegated: 1800
      // Capacity: 200 + min(200*2, 1800) = 600
      const tx = setupAllocation(tokensToAllocate)
      await expect(tx).revertedWith('Allocation: not enough tokens available to allocate')
    })

    it('should allocate using full delegation capacity', async function () {
      // 1:10 delegation capacity
      await staking.connect(governor.signer).setDelegationCapacity(10)

      // Delegate
      await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

      // Staked: 200
      // Delegated: 1800
      // Capacity: 200 + min(200*10, 1800) = 2000
      await setupAllocation(tokensToAllocate)

      // State updated
      const alloc = await staking.getAllocation(channelID)
      expect(alloc.tokens).eq(tokensToAllocate)
    })

    it('should send delegation cut of query fees to delegation pool', async function () {
      // 1:10 delegation capacity
      await staking.connect(governor.signer).setDelegationCapacity(10)

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
      await staking.connect(channelProxy.signer).collect(tokensToCollect, channelID)

      // Advance blocks to get the channel in epoch where it can be settled
      await advanceToNextEpoch(epochManager)

      // Settle
      await staking.connect(indexer.signer).settle(channelID)

      // Advance blocks to get the channel in epoch where it can be claimed
      await advanceToNextEpoch(epochManager)

      // Delegation pool before settlement
      const beforeDelegationPool = await staking.delegationPools(indexer.address)

      // Calculate tokens to claim and expected delegation fees
      const beforeAlloc = await staking.getAllocation(channelID)
      const delegationFees = percentageOf(queryFeeCut, beforeAlloc.collectedFees)
      const tokensToClaim = beforeAlloc.collectedFees.sub(delegationFees)

      // Claim from rebate pool
      const currentEpoch = await epochManager.currentEpoch()
      const tx = staking.connect(indexer.signer).claim(channelID, true)
      await expect(tx)
        .emit(staking, 'RebateClaimed')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          currentEpoch,
          beforeAlloc.settledAtEpoch,
          tokensToClaim,
          toBN('0'),
          delegationFees,
        )

      // State updated
      const afterDelegationPool = await staking.delegationPools(indexer.address)
      expect(afterDelegationPool.tokens).eq(beforeDelegationPool.tokens.add(delegationFees))
    })
  })
})

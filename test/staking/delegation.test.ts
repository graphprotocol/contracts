import { expect, use } from 'chai'
import { Wallet } from 'ethers'
import { BigNumber } from 'ethers/utils'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import * as deployment from '../lib/deployment'
import {
  advanceToNextEpoch,
  latestBlock,
  provider,
  randomHexBytes,
  toGRT,
  toBN,
} from '../lib/testHelpers'

use(solidity)

const MAX_PPM = toBN('1000000')

describe('Staking::Delegation', () => {
  const [me, delegator, governor, indexer, channelProxy] = provider().getWallets()

  let curation: Curation
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

  async function shouldDelegate(sender: Wallet, tokens: BigNumber) {
    // Calculate shares to get
    const beforePool = await staking.delegation(indexer.address)
    const shares = beforePool.tokens.eq(toBN('0'))
      ? tokens
      : tokens.mul(beforePool.tokens).div(beforePool.shares)

    // Delegate
    const tx = staking.connect(sender).delegate(indexer.address, tokens)
    await expect(tx)
      .to.emit(staking, 'StakeDelegated')
      .withArgs(indexer.address, sender.address, tokens, shares)

    // State updated
    const afterPool = await staking.delegation(indexer.address)
    expect(afterPool.tokens).to.be.eq(beforePool.tokens.add(tokens))
    expect(afterPool.shares).to.be.eq(beforePool.shares.add(shares))
  }

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
  })

  describe('configuration', function() {
    describe('delegationCapacity', function() {
      const delegationCapacity = 5

      it('should set `delegationCapacity`', async function() {
        await staking.connect(governor).setDelegationCapacity(delegationCapacity)
        expect(await staking.delegationCapacity()).to.be.eq(delegationCapacity)
      })

      it('reject set `delegationCapacity` if not allowed', async function() {
        const tx = staking.setDelegationCapacity(delegationCapacity)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('delegationParametersCooldown', function() {
      const cooldown = 5

      it('should set `delegationParametersCooldown`', async function() {
        await staking.connect(governor).setDelegationParametersCooldown(cooldown)
        expect(await staking.delegationParametersCooldown()).to.be.eq(cooldown)
      })

      it('reject set `delegationParametersCooldown` if not allowed', async function() {
        const tx = staking.setDelegationParametersCooldown(cooldown)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    describe('delegationParameters', function() {
      const indexingRewardCut = toBN('50000')
      const queryFeeCut = toBN('80000')
      const cooldownBlocks = 5

      it('reject to set if under cooldown period', async function() {
        // Set parameters
        await staking
          .connect(indexer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)

        // Try to set before cooldown period passed
        const tx = staking
          .connect(indexer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)
        await expect(tx).revertedWith(
          'Delegation: must expire cooldown period to update parameters',
        )
      })

      it('reject to set if cooldown below the global configuration', async function() {
        // Set global cooldown parameter
        await staking.connect(governor).setDelegationParametersCooldown(cooldownBlocks)

        // Try to set delegation cooldown below global cooldown parameter
        const tx = staking
          .connect(indexer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks - 1)
        await expect(tx).revertedWith('Delegation: cooldown cannot be below minimum')
      })

      it('reject to set parameters out of bound', async function() {
        // Indexing reward out of bounds
        const tx1 = staking
          .connect(indexer)
          .setDelegationParameters(MAX_PPM.add('1'), queryFeeCut, cooldownBlocks)
        await expect(tx1).revertedWith('IndexingRewardCut must be below or equal to MAX_PPM')

        // Query fee out of bounds
        const tx2 = staking
          .connect(indexer)
          .setDelegationParameters(indexingRewardCut, MAX_PPM.add('1'), cooldownBlocks)
        await expect(tx2).revertedWith('QueryFeeCut must be below or equal to MAX_PPM')
      })

      it('should set parameters', async function() {
        // Set parameters
        const tx = staking
          .connect(indexer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)
        await expect(tx)
          .to.emit(staking, 'DelegationParametersUpdated')
          .withArgs(indexer.address, indexingRewardCut, queryFeeCut, cooldownBlocks)

        // State updated
        const params = await staking.delegation(indexer.address)
        expect(params.indexingRewardCut).to.be.eq(indexingRewardCut)
        expect(params.queryFeeCut).to.be.eq(queryFeeCut)
        expect(params.cooldownBlocks).to.be.eq(cooldownBlocks)
        expect(params.updatedAtBlock).to.be.eq(await latestBlock())
      })
    })
  })

  describe('delegate', function() {
    beforeEach(async function() {
      // Distribute test funds
      await grt.connect(governor).mint(delegator.address, toGRT('10000000000000000000'))
      await grt.connect(delegator).approve(staking.address, toGRT('10000000000000000000'))
    })

    it('reject to delegate zero tokens', async function() {
      const tokensToDelegate = toGRT('0')
      const tx = staking.delegate(indexer.address, tokensToDelegate)
      await expect(tx).revertedWith('Delegation: cannot delegate zero tokens')
    })

    it('should delegate tokens and account shares proportionally', async function() {
      await shouldDelegate(delegator, toGRT('1234'))
      await shouldDelegate(delegator, toGRT('100'))
      await shouldDelegate(delegator, toGRT('50'))
      await shouldDelegate(delegator, toGRT('25'))
      await shouldDelegate(delegator, toGRT('10'))
      await shouldDelegate(delegator, toGRT('1'))
    })

    it('should delegate a high number of tokens', async function() {
      await shouldDelegate(delegator, toGRT('100'))
      await shouldDelegate(delegator, toGRT('1000000000000000000'))
    })
  })

  describe('undelegate', function() {
    beforeEach(async function() {
      // Distribute test funds
      for (const wallet of [delegator, me]) {
        await grt.connect(governor).mint(wallet.address, toGRT('1000'))
        await grt.connect(wallet).approve(staking.address, toGRT('1000'))
      }
    })

    it('reject to undelegate zero shares', async function() {
      const tx = staking.connect(delegator).undelegate(indexer.address, toGRT('0'))
      await expect(tx).revertedWith('Delegation: cannot undelegate zero shares')
    })

    it('reject to undelegate more shares than owned', async function() {
      const tx = staking.connect(delegator).undelegate(indexer.address, toGRT('100'))
      await expect(tx).revertedWith('Delegation: delegator does not have enough shares')
    })

    it('should exchange delegation pool shares for tokens', async function() {
      const tokens = toGRT('100')

      // Have two parties that delegated tokens to the same indexer
      await shouldDelegate(delegator, tokens)
      await shouldDelegate(me, tokens)

      // Get the delegation pool for the indexer
      const beforePool = await staking.delegation(indexer.address)

      // Undelegate half of one of the delegator shares
      const beforeShares = await staking.getDelegationShares(indexer.address, delegator.address)
      const sharesToUndelegate = beforeShares.div(toBN('2'))

      // Calculate the tokens to receive for the shares
      const tokensToReceive = sharesToUndelegate.mul(beforePool.shares).div(beforePool.tokens)

      // Undelegate
      const tx = staking.connect(delegator).undelegate(indexer.address, sharesToUndelegate)
      await expect(tx)
        .to.emit(staking, 'StakeUndelegated')
        .withArgs(indexer.address, delegator.address, tokensToReceive, sharesToUndelegate)

      // State updated
      const afterPool = await staking.delegation(indexer.address)
      expect(afterPool.tokens).to.be.eq(beforePool.tokens.sub(tokensToReceive))
      expect(afterPool.shares).to.be.eq(beforePool.shares.sub(sharesToUndelegate))

      const afterShares = await staking.getDelegationShares(indexer.address, delegator.address)
      expect(afterShares).to.be.eq(beforeShares.sub(sharesToUndelegate))
    })
  })

  describe('use of delegated funds', function() {
    // Default test values
    const tokensToStake = toGRT('200')
    const tokensToAllocate = toGRT('2000')
    const tokensToSettle = toGRT('1000')
    const tokensToDelegate = toGRT('1800')

    const subgraphDeploymentID = randomHexBytes()
    const channelPubKey =
      '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'

    const setupAllocation = async (tokens: BigNumber) => {
      return staking
        .connect(indexer)
        .allocate(subgraphDeploymentID, tokens, channelPubKey, channelProxy.address, toGRT('0.01'))
    }

    beforeEach(async function() {
      // Distribute test funds
      for (const wallet of [delegator, indexer, channelProxy]) {
        await grt.connect(governor).mint(wallet.address, toGRT('1000000'))
        await grt.connect(wallet).approve(staking.address, toGRT('1000000'))
      }

      // Indexer stake tokens
      await staking.connect(indexer).stake(tokensToStake)
    })

    it('revert allocate when capacity is not enough', async function() {
      // 1:2 delegation capacity
      await staking.connect(governor).setDelegationCapacity(2)

      // Delegate
      await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)

      // Staked: 200
      // Delegated: 1800
      // Capacity: 200 + min(200*2, 1800) = 600
      const tx = setupAllocation(tokensToAllocate)
      await expect(tx).revertedWith('Allocation: not enough tokens available to allocate')
    })

    it('should allocate using full delegation capacity', async function() {
      // 1:10 delegation capacity
      await staking.connect(governor).setDelegationCapacity(10)

      // Delegate
      await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)

      // Staked: 200
      // Delegated: 1800
      // Capacity: 200 + min(200*10, 1800) = 2000
      await setupAllocation(tokensToAllocate)

      // State updated
      const alloc = await staking.getAllocation(indexer.address, subgraphDeploymentID)
      expect(alloc.tokens).to.be.eq(tokensToAllocate)
    })

    it('should send delegation cut of query fees to delegation pool', async function() {
      // 1:10 delegation capacity
      await staking.connect(governor).setDelegationCapacity(10)

      // Set delegation rules for the indexer
      const indexingRewardCut = toBN('800000') // indexer keep 80%
      const queryFeeCut = toBN('950000') // indexer keeps 95%
      const cooldownBlocks = 5
      await staking
        .connect(indexer)
        .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)

      // Delegate
      await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)

      // Prepare allocation
      await setupAllocation(tokensToAllocate)

      // Advance blocks to get the channel in epoch where it can be settled
      await advanceToNextEpoch(epochManager)

      // Delegation pool before settlement
      const beforePool = await staking.delegation(indexer.address)

      // Settle
      await staking.connect(channelProxy).settle(tokensToSettle)

      // Calculate delegation fees
      const delegationFees = tokensToSettle.sub(queryFeeCut.mul(tokensToSettle).div(MAX_PPM))

      // State updated
      const afterPool = await staking.delegation(indexer.address)
      expect(afterPool.tokens).to.be.eq(beforePool.tokens.add(delegationFees))
    })
  })
})

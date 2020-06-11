import { expect, use } from 'chai'
import { Wallet } from 'ethers'
import { BigNumber } from 'ethers/utils'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import * as deployment from '../lib/deployment'
import { latestBlock, provider, toGRT, toBN } from '../lib/testHelpers'

use(solidity)

function proportion(a: BigNumber, b: BigNumber, c: BigNumber): BigNumber {
  return a.mul(c).div(b)
}

describe('Staking::Delegation', () => {
  const [me, delegator, governor, indexer] = provider().getWallets()

  let curation: Curation
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

  async function shouldDelegate(sender: Wallet, tokens: BigNumber) {
    // Calculate shares to get
    const beforePool = await staking.delegation(indexer.address)
    const shares = beforePool.tokens.eq(toBN('0'))
      ? tokens
      : proportion(tokens, beforePool.tokens, beforePool.shares)

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
      const indexingRewardCut = 50000
      const queryFeeCut = 80000
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

        // Try to set below global parameter
        const tx = staking
          .connect(indexer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks - 1)
        await expect(tx).revertedWith('Delegation: cooldown cannot be below minimum')
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
      await grt.connect(governor).mint(delegator.address, toGRT('10000000000000'))
      await grt.connect(delegator).approve(staking.address, toGRT('10000000000000'))
    })

    it('reject to delegate zero tokens', async function() {
      const tokensToDelegate = toGRT('0')
      const tx = staking.delegate(indexer.address, tokensToDelegate)
      await expect(tx).revertedWith('Delegation: cannot delegate zero tokens')
    })

    it('should delegate tokens and account shares proportionally', async function() {
      await shouldDelegate(delegator, toGRT('100'))
      await shouldDelegate(delegator, toGRT('50'))
      await shouldDelegate(delegator, toGRT('25'))
      await shouldDelegate(delegator, toGRT('10'))
    })

    it('should delegate a high number of tokens', async function() {
      await shouldDelegate(delegator, toGRT('100'))
      await shouldDelegate(delegator, toGRT('1000000000000'))
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
      const tokensToReceive = proportion(sharesToUndelegate, beforePool.shares, beforePool.tokens)

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
})

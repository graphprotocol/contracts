import { expect, use } from 'chai'
import { Event, Wallet } from 'ethers'
import { BigNumber } from 'ethers/utils'
import { AddressZero } from 'ethers/constants'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import * as deployment from '../lib/deployment'
import {
  advanceBlockTo,
  randomHexBytes,
  latestBlock,
  provider,
  toBN,
  toGRT,
} from '../lib/testHelpers'

use(solidity)

describe('Staking::Delegation', () => {
  const [me, delegator, governor, indexer, slasher] = provider().getWallets()

  let curation: Curation
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

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
        await expect(tx).to.be.revertedWith('Only Governor can call')
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
        await expect(tx).to.be.revertedWith('Only Governor can call')
      })
    })

    describe('delegationParameters', function() {
      const indexingRewardCut = 50000
      const queryFeeCut = 80000
      const cooldownBlocks = 5

      it('should set parameters', async function() {
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

      it('reject to set if under cooldown period', async function() {
        // Set parameters
        await staking
          .connect(indexer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)

        // Try to set before cooldown period passed
        const tx = staking
          .connect(indexer)
          .setDelegationParameters(indexingRewardCut, queryFeeCut, cooldownBlocks)
        await expect(tx).to.revertedWith(
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
        await expect(tx).to.revertedWith('Delegation: cooldown cannot be below minimum')
      })
    })
  })

  describe('delegate', function() {
    async function shouldDelegate(sender: Wallet, tokens: BigNumber) {
      // Calculate shares to get
      const beforePool = await staking.delegation(indexer.address)
      const shares =
        beforePool.tokens == 0 ? tokens : tokens.div(beforePool.tokens).mul(beforePool.shares)

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
      await grt.connect(governor).mint(delegator.address, toGRT('1000'))
      await grt.connect(delegator).approve(staking.address, toGRT('1000'))
    })

    it('should delegate tokens and account shares proportionally', async function() {
      await shouldDelegate(delegator, toGRT('100'))
      await shouldDelegate(delegator, toGRT('50'))
      await shouldDelegate(delegator, toGRT('25'))
    })

    it('reject to delegate zero tokens', async function() {
      const tokensToDelegate = toGRT('0')
      const tx = staking.delegate(indexer.address, tokensToDelegate)
      await expect(tx).to.revertedWith('Delegation: cannot delegate zero tokens')
    })
  })
})

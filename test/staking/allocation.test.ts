import { expect, use } from 'chai'
import { constants, utils, BigNumber } from 'ethers'
import { solidity } from 'ethereum-waffle'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'
import {
  advanceToNextEpoch,
  getAccounts,
  randomHexBytes,
  toBN,
  toGRT,
  Account,
} from '../lib/testHelpers'

use(solidity)

const { AddressZero } = constants
const { computePublicKey } = utils

const MAX_PPM = toBN('1000000')

enum AllocationState {
  Null,
  Active,
  Settled,
  Finalized,
  Claimed,
}

const calculateEffectiveAllocation = (
  tokens: BigNumber,
  numEpochs: BigNumber,
  maxAllocationEpochs: BigNumber,
) => {
  const shouldCap = maxAllocationEpochs.gt(toBN('0')) && numEpochs.gt(maxAllocationEpochs)
  return tokens.mul(shouldCap ? maxAllocationEpochs : numEpochs)
}

describe('Staking:Allocation', () => {
  let me: Account
  let other: Account
  let governor: Account
  let indexer: Account
  let slasher: Account
  let channelProxy: Account

  let fixture: NetworkFixture

  let curation: Curation
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

  // Test values
  const indexerTokens = toGRT('1000')
  const tokensToStake = toGRT('100')
  const tokensToAllocate = toGRT('100')
  const tokensToCollect = toGRT('100')
  const subgraphDeploymentID = randomHexBytes()
  const channelID = '0x6367E9dD7641e0fF221740b57B8C730031d72530'
  const channelPubKey =
    '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'
  const price = toGRT('0.01')

  // Helpers
  const allocate = (tokens: BigNumber) => {
    return staking
      .connect(indexer.signer)
      .allocate(subgraphDeploymentID, tokens, channelPubKey, channelProxy.address, price)
  }

  before(async function () {
    ;[me, other, governor, indexer, slasher, channelProxy] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ curation, epochManager, grt, staking } = await fixture.load(
      governor.signer,
      slasher.signer,
    ))

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

  /**
   * Allocate
   */
  describe('allocate', function () {
    const shouldAllocate = async (tokensToAllocate: BigNumber) => {
      // Before state
      const beforeStake = await staking.stakes(indexer.address)

      // Allocate
      const currentEpoch = await epochManager.currentEpoch()
      const tx = allocate(tokensToAllocate)
      await expect(tx)
        .emit(staking, 'AllocationCreated')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          currentEpoch,
          tokensToAllocate,
          channelID,
          channelPubKey,
          price,
        )

      // After state
      const afterStake = await staking.stakes(indexer.address)
      const afterAlloc = await staking.getAllocation(channelID)

      // Stake updated
      expect(afterStake.tokensAllocated).eq(beforeStake.tokensAllocated.add(tokensToAllocate))
      // Allocation updated
      expect(afterAlloc.indexer).eq(indexer.address)
      expect(afterAlloc.subgraphDeploymentID).eq(subgraphDeploymentID)
      expect(afterAlloc.tokens).eq(tokensToAllocate)
      expect(afterAlloc.createdAtEpoch).eq(currentEpoch)
      expect(afterAlloc.collectedFees).eq(toGRT('0'))
      expect(afterAlloc.settledAtEpoch).eq(toBN('0'))
      expect(afterAlloc.effectiveAllocation).eq(toGRT('0'))
      expect(afterAlloc.channelProxy).eq(channelProxy.address)
    }

    it('reject allocate zero tokens', async function () {
      const zeroTokens = toGRT('0')
      const tx = allocate(zeroTokens)
      await expect(tx).revertedWith('Allocation: cannot allocate zero tokens')
    })

    it('reject allocate with invalid public key', async function () {
      const invalidChannelPubKey = computePublicKey(channelPubKey, true)
      const tx = staking
        .connect(indexer.signer)
        .allocate(
          subgraphDeploymentID,
          tokensToAllocate,
          invalidChannelPubKey,
          channelProxy.address,
          price,
        )
      await expect(tx).revertedWith('Allocation: invalid channel public key')
    })

    it('reject allocate if no tokens staked', async function () {
      const tokensOverCapacity = tokensToStake.add(toBN('1'))
      const tx = allocate(tokensOverCapacity)
      await expect(tx).revertedWith('Allocation: not enough tokens available to allocate')
    })

    context('> when staked', function () {
      beforeEach(async function () {
        await staking.connect(indexer.signer).stake(tokensToStake)
      })

      it('reject allocate more than available tokens', async function () {
        const tokensOverCapacity = tokensToStake.add(toBN('1'))
        const tx = allocate(tokensOverCapacity)
        await expect(tx).revertedWith('Allocation: not enough tokens available to allocate')
      })

      it('should allocate', async function () {
        await shouldAllocate(tokensToAllocate)
      })

      it('reject allocate reusing a channel', async function () {
        const someTokensToAllocate = toGRT('10')
        await shouldAllocate(someTokensToAllocate)
        const tx = allocate(someTokensToAllocate)
        await expect(tx).revertedWith('Allocation: channel ID already used')
      })
    })
  })

  /**
   * Collect
   */
  describe('collect', function () {
    // This function tests collect with state updates
    const shouldCollect = async (tokensToCollect: BigNumber) => {
      // Before state
      const beforeTokenSupply = await grt.totalSupply()
      const beforePool = await curation.pools(subgraphDeploymentID)
      const beforeAlloc = await staking.getAllocation(channelID)

      // Advance blocks to get the channel in epoch where it can be settled
      await advanceToNextEpoch(epochManager)

      // Collect fees and calculate expected results
      let rebateFees = tokensToCollect
      const protocolPercentage = await staking.protocolPercentage()
      const protocolFees = rebateFees.mul(protocolPercentage).div(MAX_PPM)
      rebateFees = rebateFees.sub(protocolFees)

      const curationPercentage = await staking.curationPercentage()
      const curationFees = rebateFees.mul(curationPercentage).div(MAX_PPM)
      rebateFees = rebateFees.sub(curationFees)

      // Collect tokens from channel
      const tx = staking.connect(channelProxy.signer).collect(tokensToCollect, channelID)
      await expect(tx)
        .emit(staking, 'AllocationCollected')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          await epochManager.currentEpoch(),
          tokensToCollect,
          channelID,
          channelProxy.address,
          curationFees,
          rebateFees,
        )

      // After state
      const afterTokenSupply = await grt.totalSupply()
      const afterPool = await curation.pools(subgraphDeploymentID)
      const afterAlloc = await staking.getAllocation(channelID)

      // Check that protocol fees are burnt
      expect(afterTokenSupply).eq(beforeTokenSupply.sub(protocolFees))
      // Check that curation reserves increased for the SubgraphDeployment
      expect(afterPool.tokens).eq(beforePool.tokens.add(curationFees))
      // Verify allocation is updated and channel closed
      expect(afterAlloc.tokens).eq(beforeAlloc.tokens)
      expect(afterAlloc.createdAtEpoch).eq(beforeAlloc.createdAtEpoch)
      expect(afterAlloc.settledAtEpoch).eq(toBN('0'))
      expect(afterAlloc.collectedFees).eq(beforeAlloc.collectedFees.add(rebateFees))
    }

    beforeEach(async function () {
      // Create the allocation
      await staking.connect(indexer.signer).stake(tokensToStake)
      await allocate(tokensToAllocate)

      // Fund channel wallet
      const tokensToFund = toGRT('100000')
      await grt.connect(governor.signer).mint(channelProxy.address, tokensToFund)
      await grt.connect(channelProxy.signer).approve(staking.address, tokensToFund)
    })

    it('reject collect if invalid channel', async function () {
      const tx = staking.connect(indexer.signer).collect(tokensToCollect, AddressZero)
      await expect(tx).revertedWith('Collect: invalid channel')
    })

    it('reject collect if channel does not exist', async function () {
      const invalidChannelID = randomHexBytes(20)
      const tx = staking.connect(indexer.signer).collect(tokensToCollect, invalidChannelID)
      await expect(tx).revertedWith('Collect: caller is not related to the channel allocation')
    })

    it('reject collect if caller not related to channel', async function () {
      const tx = staking.connect(other.signer).collect(tokensToCollect, channelID)
      await expect(tx).revertedWith('Collect: caller is not related to the channel allocation')
    })

    it('should collect funds from channel', async function () {
      // Allow to collect from channel multiple times
      await shouldCollect(tokensToCollect)
      await shouldCollect(tokensToCollect)
      await shouldCollect(tokensToCollect)
    })

    it('should collect funds from channel and distribute curation fees', async function () {
      // Curate the subgraph from where we collect fees to get curation fees distributed
      const tokensToSignal = toGRT('100')
      await grt.connect(governor.signer).mint(me.address, tokensToSignal)
      await grt.connect(me.signer).approve(curation.address, tokensToSignal)
      await curation.connect(me.signer).mint(subgraphDeploymentID, tokensToSignal)

      // Curation parameters
      const curationPercentage = toBN('200000') // 20%
      await staking.connect(governor.signer).setCurationPercentage(curationPercentage)

      // Collect
      await shouldCollect(tokensToCollect)
    })

    it('should collect funds from channel + protocol fee + curation fees', async function () {
      // Curate the subgraph from where we collect fees to get curation fees distributed
      const tokensToSignal = toGRT('100')
      await grt.connect(governor.signer).mint(me.address, tokensToSignal)
      await grt.connect(me.signer).approve(curation.address, tokensToSignal)
      await curation.connect(me.signer).mint(subgraphDeploymentID, tokensToSignal)

      // Set a protocol fee percentage
      const protocolPercentage = toBN('100000') // 10%
      await staking.connect(governor.signer).setProtocolPercentage(protocolPercentage)

      // Set a curation fee percentage
      const curationPercentage = toBN('200000') // 20%
      await staking.connect(governor.signer).setCurationPercentage(curationPercentage)

      // Collect
      await shouldCollect(tokensToCollect)
    })

    it('should collect zero tokens', async function () {
      await shouldCollect(toGRT('0'))
    })

    it('should collect from a settling channel but reject after dispute period', async function () {
      // Set channel dispute period to one epoch
      await staking.connect(governor.signer).setChannelDisputeEpochs(toBN('1'))
      // Advance blocks to get the channel in epoch where it can be settled
      await advanceToNextEpoch(epochManager)
      // Settle the channel
      await staking.connect(indexer.signer).settle(channelID)

      // Collect fees into the channel
      const tx1 = staking.connect(channelProxy.signer).collect(tokensToCollect, channelID)
      await tx1

      // Advance blocks to get channel in epoch where it can no longer collect funds (finalized)
      await advanceToNextEpoch(epochManager)

      // Revert if channel is finalized
      expect(await staking.getAllocationState(channelID)).eq(AllocationState.Finalized)
      const tx2 = staking.connect(channelProxy.signer).collect(tokensToCollect, channelID)
      await expect(tx2).revertedWith('Collect: channel must be active or settled')
    })
  })

  /**
   * Settle
   */
  describe('settle', function () {
    beforeEach(async function () {
      // Stake and allocate channel
      await staking.connect(indexer.signer).stake(tokensToStake)
      await allocate(tokensToAllocate)
    })

    it('reject settle a non-existing channel allocation', async function () {
      const invalidChannelID = randomHexBytes(20)
      const tx = staking.connect(indexer.signer).settle(invalidChannelID)
      await expect(tx).revertedWith('Settle: channel must be active')
    })

    it('reject settle before at least one epoch has passed', async function () {
      const tx = staking.connect(indexer.signer).settle(channelID)
      await expect(tx).revertedWith('Settle: must pass at least one epoch')
    })

    it('reject settle if not the owner of channel allocation', async function () {
      // Move at least one epoch to be able to settle
      await advanceToNextEpoch(epochManager)

      // Settle
      const tx = staking.connect(me.signer).settle(channelID)
      await expect(tx).revertedWith('Settle: only indexer can settle')
    })

    it('reject settle if channel allocation is already settled', async function () {
      // Move at least one epoch to be able to settle
      await advanceToNextEpoch(epochManager)

      // First settlement
      await staking.connect(indexer.signer).settle(channelID)

      // Second settlement
      const tx = staking.connect(indexer.signer).settle(channelID)
      await expect(tx).revertedWith('Settle: channel must be active')
    })

    it('should settle a channel allocation', async function () {
      // Before state
      const beforeStake = await staking.stakes(indexer.address)
      const beforeAlloc = await staking.getAllocation(channelID)
      const beforeRebate = await staking.rebates((await epochManager.currentEpoch()).add(toBN('2')))

      // Move at least one epoch to be able to settle
      await advanceToNextEpoch(epochManager)
      await advanceToNextEpoch(epochManager)

      // Calculations
      const { 0: currentEpoch, 1: epochs } = await epochManager.epochsSince(
        beforeAlloc.createdAtEpoch,
      )
      const effectiveAllocation = calculateEffectiveAllocation(
        beforeAlloc.tokens,
        epochs,
        await staking.maxAllocationEpochs(),
      )

      // Settle
      const tx = staking.connect(indexer.signer).settle(channelID)
      await expect(tx)
        .emit(staking, 'AllocationSettled')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          currentEpoch,
          beforeAlloc.tokens,
          channelID,
          effectiveAllocation,
        )

      // After state
      const afterStake = await staking.stakes(indexer.address)
      const afterAlloc = await staking.getAllocation(channelID)
      const afterRebate = await staking.rebates(currentEpoch)

      // Stake updated
      expect(afterStake.tokensAllocated).eq(beforeStake.tokensAllocated.sub(beforeAlloc.tokens))
      // Allocation updated
      expect(afterAlloc.settledAtEpoch).eq(currentEpoch)
      expect(afterAlloc.effectiveAllocation).eq(effectiveAllocation)
      // Rebate updated
      expect(afterRebate.fees).eq(beforeRebate.fees.add(beforeAlloc.collectedFees))
      expect(afterRebate.allocation).eq(beforeRebate.allocation.add(effectiveAllocation))
      expect(afterRebate.settlementsCount).eq(beforeRebate.settlementsCount.add(toBN('1')))
    })
  })

  /**
   * Claim
   */
  describe('claim', function () {
    // Claim and perform checks
    const shouldClaim = async function (channelID: string, restake: boolean) {
      // Advance blocks to get the channel in epoch where it can be claimed
      await advanceToNextEpoch(epochManager)

      // Before state
      const beforeBalance = await grt.balanceOf(indexer.address)
      const beforeStake = await staking.stakes(indexer.address)
      const beforeAlloc = await staking.allocations(channelID)
      const beforeRebatePool = await staking.rebates(beforeAlloc.settledAtEpoch)

      // Claim rebates
      const tokensToClaim = beforeAlloc.collectedFees
      const currentEpoch = await epochManager.currentEpoch()
      const tx = staking.connect(indexer.signer).claim(channelID, restake)
      await expect(tx)
        .emit(staking, 'RebateClaimed')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          currentEpoch,
          beforeAlloc.settledAtEpoch,
          tokensToClaim,
          beforeRebatePool.settlementsCount.sub(toBN('1')),
          toGRT('0'),
        )

      // After state
      const afterBalance = await grt.balanceOf(indexer.address)
      const afterStake = await staking.stakes(indexer.address)
      const afterAlloc = await staking.allocations(channelID)
      const afterRebatePool = await staking.rebates(beforeAlloc.settledAtEpoch)

      // Funds distributed to indexer
      if (restake) {
        expect(afterBalance).eq(beforeBalance)
      } else {
        expect(afterBalance).eq(beforeBalance.add(tokensToClaim))
      }
      // Stake updated
      if (restake) {
        expect(afterStake.tokensStaked).eq(beforeStake.tokensStaked.add(tokensToClaim))
      } else {
        expect(afterStake.tokensStaked).eq(beforeStake.tokensStaked)
      }
      // Allocation updated (purged)
      expect(afterAlloc.tokens).eq(toGRT('0'))
      expect(afterAlloc.createdAtEpoch).eq(toGRT('0'))
      expect(afterAlloc.settledAtEpoch).eq(toGRT('0'))
      expect(afterAlloc.collectedFees).eq(toGRT('0'))
      expect(afterAlloc.effectiveAllocation).eq(toGRT('0'))
      expect(afterAlloc.channelProxy).eq(AddressZero)
      // Rebate updated
      expect(afterRebatePool.settlementsCount).eq(beforeRebatePool.settlementsCount.sub(toBN('1')))
      if (afterRebatePool.settlementsCount.eq(toBN('0'))) {
        // Rebate pool is empty and then pruned
        expect(afterRebatePool.allocation).eq(toGRT('0'))
        expect(afterRebatePool.fees).eq(toGRT('0'))
      } else {
        // There are still more settlements in the rebate
        expect(afterRebatePool.allocation).eq(beforeRebatePool.allocation)
        expect(afterRebatePool.fees).eq(beforeRebatePool.fees.sub(tokensToClaim))
      }
    }

    beforeEach(async function () {
      // Stake and allocate channel
      await staking.connect(indexer.signer).stake(tokensToStake)
      await allocate(tokensToAllocate)

      // Set channel dispute period to one epoch
      await staking.connect(governor.signer).setChannelDisputeEpochs(toBN('1'))

      // Fund wallets
      await grt.connect(governor.signer).mint(channelProxy.address, tokensToCollect)
      await grt.connect(channelProxy.signer).approve(staking.address, tokensToCollect)
    })

    it('reject claim for non-existing channel allocation', async function () {
      expect(await staking.getAllocationState(channelID)).eq(AllocationState.Active)
      const invalidChannelID = randomHexBytes(20)
      const tx = staking.connect(indexer.signer).claim(invalidChannelID, false)
      await expect(tx).revertedWith('Rebate: channel must be in finalized state')
    })

    it('reject claim if channel allocation is not settled', async function () {
      expect(await staking.getAllocationState(channelID)).not.eq(AllocationState.Settled)
      const tx = staking.connect(indexer.signer).claim(channelID, false)
      await expect(tx).revertedWith('Rebate: channel must be in finalized state')
    })

    context('> when settled', function () {
      beforeEach(async function () {
        // Collect some funds
        await staking.connect(channelProxy.signer).collect(tokensToCollect, channelID)

        // Advance blocks to get the channel in epoch where it can be settled
        await advanceToNextEpoch(epochManager)

        // Settle the channel allocation
        await staking.connect(indexer.signer).settle(channelID)
      })

      it('reject claim if settled but channel dispute epochs has not passed', async function () {
        expect(await staking.getAllocationState(channelID)).eq(AllocationState.Settled)
        const tx = staking.connect(indexer.signer).claim(channelID, false)
        await expect(tx).revertedWith('Rebate: channel must be in finalized state')
      })

      it('should claim rebate', async function () {
        // Advance blocks to get the channel finalized
        await advanceToNextEpoch(epochManager)

        // Before state
        const beforeIndexerTokens = await grt.balanceOf(indexer.address)

        // Claim with no restake
        expect(await staking.getAllocationState(channelID)).eq(AllocationState.Finalized)
        await shouldClaim(channelID, false)

        // Verify that the claimed tokens are transferred to the indexer
        const afterIndexerTokens = await grt.balanceOf(indexer.address)
        expect(afterIndexerTokens).eq(beforeIndexerTokens.add(tokensToCollect))
      })

      it('should claim rebate with restake', async function () {
        // Advance blocks to get the channel finalized
        await advanceToNextEpoch(epochManager)

        // Before state
        const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

        // Claim with restake
        expect(await staking.getAllocationState(channelID)).eq(AllocationState.Finalized)
        await shouldClaim(channelID, true)

        // Verify that the claimed tokens are restaked
        const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
        expect(afterIndexerStake).eq(beforeIndexerStake.add(tokensToCollect))
      })

      it('reject claim if already claimed', async function () {
        // Advance blocks to get the channel finalized
        await advanceToNextEpoch(epochManager)

        // First claim
        await shouldClaim(channelID, false)

        // Try to claim again
        expect(await staking.getAllocationState(channelID)).eq(AllocationState.Claimed)
        const tx = staking.connect(indexer.signer).claim(channelID, false)
        await expect(tx).revertedWith('Rebate: channel must be in finalized state')
      })
    })
  })
})

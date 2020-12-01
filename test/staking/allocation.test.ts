import { expect } from 'chai'
import { constants, BigNumber, ethers } from 'ethers'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'
import {
  advanceToNextEpoch,
  deriveChannelKey,
  getAccounts,
  randomHexBytes,
  toBN,
  toGRT,
  Account,
} from '../lib/testHelpers'

const { AddressZero, HashZero } = constants

const MAX_PPM = toBN('1000000')

enum AllocationState {
  Null,
  Active,
  Closed,
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
  let governor: Account
  let indexer: Account
  let slasher: Account
  let assetHolder: Account

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
  const channelKey = deriveChannelKey()
  const allocationID = channelKey.address
  const metadata = randomHexBytes(32)
  const poi = randomHexBytes()

  // Helpers
  const allocate = async (tokens: BigNumber) => {
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

  before(async function () {
    ;[me, governor, indexer, slasher, assetHolder] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ curation, epochManager, grt, staking } = await fixture.load(
      governor.signer,
      slasher.signer,
    ))

    // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
    await grt.connect(governor.signer).mint(indexer.address, indexerTokens)
    await grt.connect(indexer.signer).approve(staking.address, indexerTokens)

    // Allow the asset holder
    await staking.connect(governor.signer).setAssetHolder(assetHolder.address, true)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('operators', function () {
    it('should set operator', async function () {
      // Before state
      const beforeOperator = await staking.operatorAuth(indexer.address, me.address)

      // Set operator
      const tx = staking.connect(indexer.signer).setOperator(me.address, true)
      await expect(tx).emit(staking, 'SetOperator').withArgs(indexer.address, me.address, true)

      // After state
      const afterOperator = await staking.operatorAuth(indexer.address, me.address)

      // State updated
      expect(beforeOperator).eq(false)
      expect(afterOperator).eq(true)
    })

    it('should unset operator', async function () {
      await staking.connect(indexer.signer).setOperator(me.address, true)

      // Before state
      const beforeOperator = await staking.operatorAuth(indexer.address, me.address)

      // Set operator
      const tx = staking.connect(indexer.signer).setOperator(me.address, false)
      await expect(tx).emit(staking, 'SetOperator').withArgs(indexer.address, me.address, false)

      // After state
      const afterOperator = await staking.operatorAuth(indexer.address, me.address)

      // State updated
      expect(beforeOperator).eq(true)
      expect(afterOperator).eq(false)
    })
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
          allocationID,
          metadata,
        )

      // After state
      const afterStake = await staking.stakes(indexer.address)
      const afterAlloc = await staking.getAllocation(allocationID)

      // Stake updated
      expect(afterStake.tokensAllocated).eq(beforeStake.tokensAllocated.add(tokensToAllocate))
      // Allocation updated
      expect(afterAlloc.indexer).eq(indexer.address)
      expect(afterAlloc.subgraphDeploymentID).eq(subgraphDeploymentID)
      expect(afterAlloc.tokens).eq(tokensToAllocate)
      expect(afterAlloc.createdAtEpoch).eq(currentEpoch)
      expect(afterAlloc.collectedFees).eq(toGRT('0'))
      expect(afterAlloc.closedAtEpoch).eq(toBN('0'))
      expect(afterAlloc.effectiveAllocation).eq(toGRT('0'))
    }

    it('reject allocate zero tokens', async function () {
      const zeroTokens = toGRT('0')
      const tx = allocate(zeroTokens)
      await expect(tx).revertedWith('!tokens')
    })

    it('reject allocate with invalid allocationID', async function () {
      const tx = staking
        .connect(indexer.signer)
        .allocate(subgraphDeploymentID, tokensToAllocate, AddressZero, metadata, randomHexBytes(20))
      await expect(tx).revertedWith('!alloc')
    })

    it('reject allocate if no tokens staked', async function () {
      const tokensOverCapacity = tokensToStake.add(toBN('1'))
      const tx = allocate(tokensOverCapacity)
      await expect(tx).revertedWith('!capacity')
    })

    context('> when staked', function () {
      beforeEach(async function () {
        await staking.connect(indexer.signer).stake(tokensToStake)
      })

      it('reject allocate more than available tokens', async function () {
        const tokensOverCapacity = tokensToStake.add(toBN('1'))
        const tx = allocate(tokensOverCapacity)
        await expect(tx).revertedWith('!capacity')
      })

      it('should allocate', async function () {
        await shouldAllocate(tokensToAllocate)
      })

      it('should allocate on behalf of indexer', async function () {
        const proof = await channelKey.generateProof(indexer.address)

        // Reject to allocate if the address is not operator
        const tx1 = staking
          .connect(me.signer)
          .allocateFrom(
            indexer.address,
            subgraphDeploymentID,
            tokensToAllocate,
            allocationID,
            metadata,
            proof,
          )
        await expect(tx1).revertedWith('!auth')

        // Should allocate if given operator auth
        await staking.connect(indexer.signer).setOperator(me.address, true)
        await staking
          .connect(me.signer)
          .allocateFrom(
            indexer.address,
            subgraphDeploymentID,
            tokensToAllocate,
            allocationID,
            metadata,
            proof,
          )
      })

      it('reject allocate reusing an allocation ID', async function () {
        const someTokensToAllocate = toGRT('10')
        await shouldAllocate(someTokensToAllocate)
        const tx = allocate(someTokensToAllocate)
        await expect(tx).revertedWith('!null')
      })

      describe('reject allocate on invalid proof', function () {
        it('invalid message', async function () {
          const invalidProof = await channelKey.generateProof(randomHexBytes(20))
          const tx = staking
            .connect(indexer.signer)
            .allocate(
              subgraphDeploymentID,
              tokensToAllocate,
              indexer.address,
              metadata,
              invalidProof,
            )
          await expect(tx).revertedWith('!proof')
        })

        it('invalid proof signature format', async function () {
          const tx = staking
            .connect(indexer.signer)
            .allocate(
              subgraphDeploymentID,
              tokensToAllocate,
              indexer.address,
              metadata,
              randomHexBytes(32),
            )
          await expect(tx).revertedWith('ECDSA: invalid signature length')
        })
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
      const beforeAlloc = await staking.getAllocation(allocationID)

      // Advance blocks to get the allocation in epoch where it can be closed
      await advanceToNextEpoch(epochManager)

      // Collect fees and calculate expected results
      let rebateFees = tokensToCollect
      const protocolPercentage = await staking.protocolPercentage()
      const protocolFees = rebateFees.mul(protocolPercentage).div(MAX_PPM)
      rebateFees = rebateFees.sub(protocolFees)

      const curationPercentage = await staking.curationPercentage()
      const curationFees = rebateFees.mul(curationPercentage).div(MAX_PPM)
      rebateFees = rebateFees.sub(curationFees)

      // Collect tokens from allocation
      const tx = staking.connect(assetHolder.signer).collect(tokensToCollect, allocationID)
      await expect(tx)
        .emit(staking, 'AllocationCollected')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          await epochManager.currentEpoch(),
          tokensToCollect,
          allocationID,
          assetHolder.address,
          curationFees,
          rebateFees,
        )

      // After state
      const afterTokenSupply = await grt.totalSupply()
      const afterPool = await curation.pools(subgraphDeploymentID)
      const afterAlloc = await staking.getAllocation(allocationID)

      // Check that protocol fees are burnt
      expect(afterTokenSupply).eq(beforeTokenSupply.sub(protocolFees))
      // Check that curation reserves increased for the SubgraphDeployment
      expect(afterPool.tokens).eq(beforePool.tokens.add(curationFees))
      // Verify allocation is updated and allocation cleaned
      expect(afterAlloc.tokens).eq(beforeAlloc.tokens)
      expect(afterAlloc.createdAtEpoch).eq(beforeAlloc.createdAtEpoch)
      expect(afterAlloc.closedAtEpoch).eq(toBN('0'))
      expect(afterAlloc.collectedFees).eq(beforeAlloc.collectedFees.add(rebateFees))
    }

    beforeEach(async function () {
      // Create the allocation
      await staking.connect(indexer.signer).stake(tokensToStake)
      await allocate(tokensToAllocate)

      // Fund asset holder wallet
      const tokensToFund = toGRT('100000')
      await grt.connect(governor.signer).mint(assetHolder.address, tokensToFund)
      await grt.connect(assetHolder.signer).approve(staking.address, tokensToFund)
    })

    it('reject collect if invalid collection', async function () {
      const tx = staking.connect(indexer.signer).collect(tokensToCollect, AddressZero)
      await expect(tx).revertedWith('!alloc')
    })

    it('reject collect if allocation does not exist', async function () {
      const invalidAllocationID = randomHexBytes(20)
      const tx = staking.connect(assetHolder.signer).collect(tokensToCollect, invalidAllocationID)
      await expect(tx).revertedWith('!collect')
    })

    // NOTE: Disabled as part of deactivating the authorized sender requirement
    // it('reject collect if caller not related to allocation', async function () {
    //   const tx = staking.connect(other.signer).collect(tokensToCollect, allocationID)
    //   await expect(tx).revertedWith('caller is not authorized')
    // })

    it('should collect funds from asset holder', async function () {
      // Allow to collect from asset holder multiple times
      await shouldCollect(tokensToCollect)
      await shouldCollect(tokensToCollect)
      await shouldCollect(tokensToCollect)
    })

    it('should collect funds from asset holder and distribute curation fees', async function () {
      // Curate the subgraph from where we collect fees to get curation fees distributed
      const tokensToSignal = toGRT('100')
      await grt.connect(governor.signer).mint(me.address, tokensToSignal)
      await grt.connect(me.signer).approve(curation.address, tokensToSignal)
      await curation.connect(me.signer).mint(subgraphDeploymentID, tokensToSignal, 0)

      // Curation parameters
      const curationPercentage = toBN('200000') // 20%
      await staking.connect(governor.signer).setCurationPercentage(curationPercentage)

      // Collect
      await shouldCollect(tokensToCollect)
    })

    it('should collect funds from asset holder + protocol fee + curation fees', async function () {
      // Curate the subgraph from where we collect fees to get curation fees distributed
      const tokensToSignal = toGRT('100')
      await grt.connect(governor.signer).mint(me.address, tokensToSignal)
      await grt.connect(me.signer).approve(curation.address, tokensToSignal)
      await curation.connect(me.signer).mint(subgraphDeploymentID, tokensToSignal, 0)

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

    it('should collect from a settling allocation but reject after dispute period', async function () {
      // Set channel dispute period to one epoch
      await staking.connect(governor.signer).setChannelDisputeEpochs(toBN('1'))
      // Advance blocks to get the allocation in epoch where it can be closed
      await advanceToNextEpoch(epochManager)
      // Close the allocation
      await staking.connect(indexer.signer).closeAllocation(allocationID, poi)

      // Collect fees into the allocation
      const tx1 = staking.connect(assetHolder.signer).collect(tokensToCollect, allocationID)
      await tx1

      // Advance blocks to get allocation in epoch where it can no longer collect funds (finalized)
      await advanceToNextEpoch(epochManager)

      // Before state
      const beforeTotalSupply = await grt.totalSupply()

      // Revert if allocation is finalized
      expect(await staking.getAllocationState(allocationID)).eq(AllocationState.Finalized)
      const tx2 = staking.connect(assetHolder.signer).collect(tokensToCollect, allocationID)
      await expect(tx2)
        .emit(staking, 'AllocationCollected')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          await epochManager.currentEpoch(),
          tokensToCollect,
          allocationID,
          assetHolder.address,
          0,
          0,
        )

      // Check funds are effectively burned
      const afterTotalSupply = await grt.totalSupply()
      expect(afterTotalSupply).eq(beforeTotalSupply.sub(tokensToCollect))
    })
  })

  /**
   * Close allocation
   */
  describe('closeAllocation', function () {
    beforeEach(async function () {
      // Stake and allocate
      await staking.connect(indexer.signer).stake(tokensToStake)
      await allocate(tokensToAllocate)
    })

    it('reject close a non-existing allocation', async function () {
      const invalidAllocationID = randomHexBytes(20)
      const tx = staking.connect(indexer.signer).closeAllocation(invalidAllocationID, poi)
      await expect(tx).revertedWith('!active')
    })

    it('reject close before at least one epoch has passed', async function () {
      const tx = staking.connect(indexer.signer).closeAllocation(allocationID, poi)
      await expect(tx).revertedWith('<epochs')
    })

    it('reject close if not the owner of allocation', async function () {
      // Move at least one epoch to be able to close
      await advanceToNextEpoch(epochManager)

      // Close allocation
      const tx = staking.connect(me.signer).closeAllocation(allocationID, poi)
      await expect(tx).revertedWith('!auth')
    })

    it('reject close if allocation is already closed', async function () {
      // Move at least one epoch to be able to close
      await advanceToNextEpoch(epochManager)

      // First closing
      await staking.connect(indexer.signer).closeAllocation(allocationID, poi)

      // Second closing
      const tx = staking.connect(indexer.signer).closeAllocation(allocationID, poi)
      await expect(tx).revertedWith('!active')
    })

    it('should close an allocation', async function () {
      // Before state
      const beforeStake = await staking.stakes(indexer.address)
      const beforeAlloc = await staking.getAllocation(allocationID)
      const beforeRebatePool = await staking.rebates(
        (await epochManager.currentEpoch()).add(toBN('2')),
      )

      // Move at least one epoch to be able to close
      await advanceToNextEpoch(epochManager)
      await advanceToNextEpoch(epochManager)

      // Calculations
      const currentEpoch = await epochManager.currentEpoch()
      const epochs = currentEpoch.sub(beforeAlloc.createdAtEpoch)
      const maxAllocationEpochs = toBN(await staking.maxAllocationEpochs())
      const effectiveAllocation = calculateEffectiveAllocation(
        beforeAlloc.tokens,
        epochs,
        maxAllocationEpochs,
      )

      // Close allocation
      const tx = staking.connect(indexer.signer).closeAllocation(allocationID, poi)
      await expect(tx)
        .emit(staking, 'AllocationClosed')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          currentEpoch,
          beforeAlloc.tokens,
          allocationID,
          effectiveAllocation,
          indexer.address,
          poi,
          false,
        )

      // After state
      const afterStake = await staking.stakes(indexer.address)
      const afterAlloc = await staking.getAllocation(allocationID)
      const afterRebatePool = await staking.rebates(currentEpoch)

      // Stake updated
      expect(afterStake.tokensAllocated).eq(beforeStake.tokensAllocated.sub(beforeAlloc.tokens))
      // Allocation updated
      expect(afterAlloc.closedAtEpoch).eq(currentEpoch)
      expect(afterAlloc.effectiveAllocation).eq(effectiveAllocation)
      // Rebate updated
      expect(afterRebatePool.fees).eq(beforeRebatePool.fees.add(beforeAlloc.collectedFees))
      expect(afterRebatePool.effectiveAllocatedStake).eq(
        beforeRebatePool.effectiveAllocatedStake.add(effectiveAllocation),
      )
      expect(afterRebatePool.unclaimedAllocationsCount).eq(
        beforeRebatePool.unclaimedAllocationsCount + 1,
      )
    })

    it('should close an allocation (by operator)', async function () {
      // Move at least one epoch to be able to close
      await advanceToNextEpoch(epochManager)
      await advanceToNextEpoch(epochManager)

      // Reject to close if the address is not operator
      const tx1 = staking.connect(me.signer).closeAllocation(allocationID, poi)
      await expect(tx1).revertedWith('!auth')

      // Should close if given operator auth
      await staking.connect(indexer.signer).setOperator(me.address, true)
      await staking.connect(me.signer).closeAllocation(allocationID, poi)
    })

    it('should close an allocation (by delegator)', async function () {
      // Move max allocation epochs to close by delegator
      const maxAllocationEpochs = await staking.maxAllocationEpochs()
      for (let i = 0; i < maxAllocationEpochs + 1; i++) {
        await advanceToNextEpoch(epochManager)
      }

      // Reject to close if the address is not delegator
      const tx1 = staking.connect(me.signer).closeAllocation(allocationID, poi)
      await expect(tx1).revertedWith('!auth')

      // Calculations
      const beforeAlloc = await staking.getAllocation(allocationID)
      const currentEpoch = await epochManager.currentEpoch()
      const epochs = currentEpoch.sub(beforeAlloc.createdAtEpoch)
      const effectiveAllocation = calculateEffectiveAllocation(
        beforeAlloc.tokens,
        epochs,
        toBN(maxAllocationEpochs),
      )

      // Setup
      await grt.connect(governor.signer).mint(me.address, toGRT('1'))
      await grt.connect(me.signer).approve(staking.address, toGRT('1'))
      await staking.connect(me.signer).delegate(indexer.address, toGRT('1'))

      // Should close by delegator
      const tx = staking.connect(me.signer).closeAllocation(allocationID, poi)
      await expect(tx)
        .emit(staking, 'AllocationClosed')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          currentEpoch,
          beforeAlloc.tokens,
          allocationID,
          effectiveAllocation,
          me.address,
          poi,
          true,
        )
    })

    it('should close many allocations in batch', async function () {
      // Setup a second allocation
      await staking.connect(indexer.signer).stake(tokensToAllocate)
      const channelKey2 = deriveChannelKey()
      const allocationID2 = channelKey2.address
      await staking
        .connect(indexer.signer)
        .allocate(
          subgraphDeploymentID,
          tokensToAllocate,
          allocationID2,
          metadata,
          await channelKey2.generateProof(indexer.address),
        )

      // Move at least one epoch to be able to close
      await advanceToNextEpoch(epochManager)
      await advanceToNextEpoch(epochManager)

      // Close multiple allocations in one tx
      const requests = [
        {
          allocationID: allocationID,
          poi: poi,
        },
        {
          allocationID: allocationID2,
          poi: poi,
        },
      ]
      await staking.connect(indexer.signer).closeAllocationMany(requests)
    })
  })

  describe('closeAndAllocate', function () {
    beforeEach(async function () {
      // Stake and allocate
      await staking.connect(indexer.signer).stake(tokensToAllocate)
      await allocate(tokensToAllocate)
    })

    it('should close and create a new allocation', async function () {
      // Move at least one epoch to be able to close
      await advanceToNextEpoch(epochManager)

      // Close and allocate
      const newChannelKey = deriveChannelKey()
      const newAllocationID = newChannelKey.address
      const tx = staking
        .connect(indexer.signer)
        .closeAndAllocate(
          allocationID,
          HashZero,
          indexer.address,
          subgraphDeploymentID,
          tokensToAllocate,
          newAllocationID,
          metadata,
          await newChannelKey.generateProof(indexer.address),
        )
      await tx
    })
  })

  /**
   * Claim
   */
  describe('claim', function () {
    // Claim and perform checks
    const shouldClaim = async function (allocationID: string, restake: boolean) {
      // Advance blocks to get the allocation in epoch where it can be claimed
      await advanceToNextEpoch(epochManager)

      // Before state
      const beforeBalance = await grt.balanceOf(indexer.address)
      const beforeStake = await staking.stakes(indexer.address)
      const beforeAlloc = await staking.allocations(allocationID)
      const beforeRebatePool = await staking.rebates(beforeAlloc.closedAtEpoch)

      // Claim rebates
      const tokensToClaim = beforeAlloc.collectedFees
      const currentEpoch = await epochManager.currentEpoch()
      const tx = staking.connect(indexer.signer).claim(allocationID, restake)
      await expect(tx)
        .emit(staking, 'RebateClaimed')
        .withArgs(
          indexer.address,
          subgraphDeploymentID,
          allocationID,
          currentEpoch,
          beforeAlloc.closedAtEpoch,
          tokensToClaim,
          beforeRebatePool.unclaimedAllocationsCount - 1,
          toGRT('0'),
        )

      // After state
      const afterBalance = await grt.balanceOf(indexer.address)
      const afterStake = await staking.stakes(indexer.address)
      const afterAlloc = await staking.allocations(allocationID)
      const afterRebatePool = await staking.rebates(beforeAlloc.closedAtEpoch)

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
      expect(afterAlloc.closedAtEpoch).eq(toGRT('0'))
      expect(afterAlloc.collectedFees).eq(toGRT('0'))
      expect(afterAlloc.effectiveAllocation).eq(toGRT('0'))
      expect(afterAlloc.accRewardsPerAllocatedToken).eq(toGRT('0'))
      // Rebate updated
      expect(afterRebatePool.unclaimedAllocationsCount).eq(
        beforeRebatePool.unclaimedAllocationsCount - 1,
      )
      if (afterRebatePool.unclaimedAllocationsCount === 0) {
        // Rebate pool is empty and then pruned
        expect(afterRebatePool.effectiveAllocatedStake).eq(toGRT('0'))
        expect(afterRebatePool.fees).eq(toGRT('0'))
      } else {
        // There are still more unclaimed allocations in the rebate pool
        expect(afterRebatePool.effectiveAllocatedStake).eq(beforeRebatePool.effectiveAllocatedStake)
        expect(afterRebatePool.fees).eq(beforeRebatePool.fees.sub(tokensToClaim))
      }
    }

    beforeEach(async function () {
      // Stake and allocate
      await staking.connect(indexer.signer).stake(tokensToStake)
      await allocate(tokensToAllocate)

      // Set channel dispute period to one epoch
      await staking.connect(governor.signer).setChannelDisputeEpochs(toBN('1'))

      // Fund wallets
      await grt.connect(governor.signer).mint(assetHolder.address, tokensToCollect)
      await grt.connect(assetHolder.signer).approve(staking.address, tokensToCollect)
    })

    it('reject claim for non-existing allocation', async function () {
      expect(await staking.getAllocationState(allocationID)).eq(AllocationState.Active)
      const invalidAllocationID = randomHexBytes(20)
      const tx = staking.connect(indexer.signer).claim(invalidAllocationID, false)
      await expect(tx).revertedWith('!finalized')
    })

    it('reject claim if allocation is not closed', async function () {
      expect(await staking.getAllocationState(allocationID)).not.eq(AllocationState.Closed)
      const tx = staking.connect(indexer.signer).claim(allocationID, false)
      await expect(tx).revertedWith('!finalized')
    })

    context('> when allocation closed', function () {
      beforeEach(async function () {
        // Collect some funds
        await staking.connect(assetHolder.signer).collect(tokensToCollect, allocationID)

        // Advance blocks to get the allocation in epoch where it can be closed
        await advanceToNextEpoch(epochManager)

        // Close the allocation
        await staking.connect(indexer.signer).closeAllocation(allocationID, poi)
      })

      it('reject claim if closed but channel dispute epochs has not passed', async function () {
        expect(await staking.getAllocationState(allocationID)).eq(AllocationState.Closed)
        const tx = staking.connect(indexer.signer).claim(allocationID, false)
        await expect(tx).revertedWith('!finalized')
      })

      it('should claim rebate', async function () {
        // Advance blocks to get the allocation finalized
        await advanceToNextEpoch(epochManager)

        // Before state
        const beforeIndexerTokens = await grt.balanceOf(indexer.address)

        // Claim with no restake
        expect(await staking.getAllocationState(allocationID)).eq(AllocationState.Finalized)
        await shouldClaim(allocationID, false)

        // Verify that the claimed tokens are transferred to the indexer
        const afterIndexerTokens = await grt.balanceOf(indexer.address)
        expect(afterIndexerTokens).eq(beforeIndexerTokens.add(tokensToCollect))
      })

      it('should claim rebate with restake', async function () {
        // Advance blocks to get the allocation finalized
        await advanceToNextEpoch(epochManager)

        // Before state
        const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

        // Claim with restake
        expect(await staking.getAllocationState(allocationID)).eq(AllocationState.Finalized)
        await shouldClaim(allocationID, true)

        // Verify that the claimed tokens are restaked
        const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
        expect(afterIndexerStake).eq(beforeIndexerStake.add(tokensToCollect))
      })

      it('should claim rebate (by public)', async function () {
        // Advance blocks to get the allocation in epoch where it can be claimed
        await advanceToNextEpoch(epochManager)

        // Should claim by public, but cannot restake
        const beforeIndexerStake = await staking.stakes(indexer.address)
        await staking.connect(me.signer).claim(allocationID, true)
        const afterIndexerStake = await staking.stakes(indexer.address)
        expect(afterIndexerStake.tokensStaked).eq(beforeIndexerStake.tokensStaked)
      })

      it('should claim rebate (by operator)', async function () {
        // Advance blocks to get the allocation in epoch where it can be claimed
        await advanceToNextEpoch(epochManager)

        // Add as operator
        await staking.connect(indexer.signer).setOperator(me.address, true)

        // Should claim if given operator auth and can do restake
        const beforeIndexerStake = await staking.stakes(indexer.address)
        await staking.connect(me.signer).claim(allocationID, true)
        const afterIndexerStake = await staking.stakes(indexer.address)
        expect(afterIndexerStake.tokensStaked).not.eq(beforeIndexerStake.tokensStaked)
      })

      it('should claim many rebates with restake', async function () {
        // Advance blocks to get the allocation in epoch where it can be claimed
        await advanceToNextEpoch(epochManager)

        // Before state
        const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer.address)

        // Claim with restake
        expect(await staking.getAllocationState(allocationID)).eq(AllocationState.Finalized)
        await staking.connect(indexer.signer).claimMany([allocationID], true)

        // Verify that the claimed tokens are restaked
        const afterIndexerStake = await staking.getIndexerStakedTokens(indexer.address)
        expect(afterIndexerStake).eq(beforeIndexerStake.add(tokensToCollect))
      })

      it('reject claim if already claimed', async function () {
        // Advance blocks to get the allocation finalized
        await advanceToNextEpoch(epochManager)

        // First claim
        await shouldClaim(allocationID, false)

        // Try to claim again
        expect(await staking.getAllocationState(allocationID)).eq(AllocationState.Claimed)
        const tx = staking.connect(indexer.signer).claim(allocationID, false)
        await expect(tx).revertedWith('!finalized')
      })
    })
  })
})

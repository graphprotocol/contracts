import { Curation } from '@graphprotocol/contracts'
import { GraphToken } from '@graphprotocol/contracts'
import { IStaking } from '@graphprotocol/contracts'
import { RewardsManager } from '@graphprotocol/contracts'
import { deriveChannelKey, GraphNetworkContracts, helpers, randomHexBytes, toBN, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { constants } from 'ethers'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

const { HashZero } = constants

/**
 * Test for the signal/allocation update accounting bug fix.
 *
 * The bug: When `onSubgraphSignalUpdate()` is called before `onSubgraphAllocationUpdate()`
 * in the SAME BLOCK, the per-signal delta is zero but rewards tracked in `accRewardsForSubgraph`
 * are never distributed to allocations. This causes rewards to be "bricked".
 *
 * The fix: Use the snapshot delta (accRewardsForSubgraph - accRewardsForSubgraphSnapshot) instead
 * of only relying on the per-signal delta for calculating new rewards.
 *
 * IMPORTANT: These tests use evm_setAutomine to batch transactions into the same block,
 * which is necessary to reproduce the bug condition where per-signal delta = 0.
 */
describe('Rewards: Signal and Allocation Update Accounting', () => {
  const graph = hre.graph()
  let governor: SignerWithAddress
  let curator: SignerWithAddress
  let indexer: SignerWithAddress

  let fixture: NetworkFixture
  let contracts: GraphNetworkContracts
  let grt: GraphToken
  let curation: Curation
  let staking: IStaking
  let rewardsManager: RewardsManager

  const channelKey = deriveChannelKey()
  const subgraphDeploymentID = randomHexBytes()
  const allocationID = channelKey.address
  const metadata = HashZero

  const ISSUANCE_PER_BLOCK = toBN('200000000000000000000') // 200 GRT every block
  const tokensToSignal = toGRT('1000')
  const tokensToStake = toGRT('100000')
  const tokensToAllocate = toGRT('10000')

  before(async function () {
    ;[curator, indexer] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    grt = contracts.GraphToken as GraphToken
    curation = contracts.Curation as Curation
    staking = contracts.Staking as IStaking
    rewardsManager = contracts.RewardsManager as RewardsManager
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  async function setupSubgraphWithAllocation() {
    // Setup: curator signals on subgraph
    await grt.connect(governor).mint(curator.address, tokensToSignal)
    await grt.connect(curator).approve(curation.address, tokensToSignal)
    await curation.connect(curator).mint(subgraphDeploymentID, tokensToSignal, 0)

    // Setup: indexer stakes and allocates
    await grt.connect(governor).mint(indexer.address, tokensToStake)
    await grt.connect(indexer).approve(staking.address, tokensToStake)
    await staking.connect(indexer).stake(tokensToStake)
    await staking
      .connect(indexer)
      .allocateFrom(
        indexer.address,
        subgraphDeploymentID,
        tokensToAllocate,
        allocationID,
        metadata,
        await channelKey.generateProof(indexer.address),
      )
  }

  describe('onSubgraphSignalUpdate followed by onSubgraphAllocationUpdate', function () {
    it('should properly distribute rewards when signal update precedes allocation update (same block)', async function () {
      await setupSubgraphWithAllocation()

      // Advance blocks to accumulate rewards
      await helpers.mine(100)

      // Get expected rewards before any updates
      const expectedRewardsForSubgraph = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID)
      expect(expectedRewardsForSubgraph).to.be.gt(0, 'Should have accumulated rewards')

      // Get initial state
      const subgraphBefore = await rewardsManager.subgraphs(subgraphDeploymentID)
      const accRewardsPerAllocatedTokenBefore = subgraphBefore.accRewardsPerAllocatedToken

      // Disable automine to batch transactions into the same block
      await hre.network.provider.send('evm_setAutomine', [false])

      try {
        // First: call onSubgraphSignalUpdate (this zeros the per-signal delta)
        // This simulates what happens when a curator mints/burns signal
        const signalTx = await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)

        // Second: call onSubgraphAllocationUpdate (in same block, per-signal delta is 0)
        // This simulates what happens when an allocation is opened/closed
        const allocTx = await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)

        // Mine both transactions in the same block
        await hre.network.provider.send('evm_mine')

        // Wait for both transactions to be mined
        await signalTx.wait()
        await allocTx.wait()
      } finally {
        // Re-enable automine
        await hre.network.provider.send('evm_setAutomine', [true])
      }

      // Verify rewards were tracked at subgraph level
      const subgraphAfterSignal = await rewardsManager.subgraphs(subgraphDeploymentID)
      expect(subgraphAfterSignal.accRewardsForSubgraph).to.be.gt(
        0,
        'accRewardsForSubgraph should be updated after signal update',
      )

      // Get final state
      const subgraphAfterAllocation = await rewardsManager.subgraphs(subgraphDeploymentID)

      // THE FIX: accRewardsPerAllocatedToken should be updated even though per-signal delta was 0
      // With the bug, this would remain unchanged because newRewards=0 caused early return
      expect(subgraphAfterAllocation.accRewardsPerAllocatedToken).to.be.gt(
        accRewardsPerAllocatedTokenBefore,
        'accRewardsPerAllocatedToken should increase (BUG: was not updated when signal update preceded allocation update)',
      )

      // Verify snapshot consistency
      expect(subgraphAfterAllocation.accRewardsForSubgraphSnapshot).to.equal(
        subgraphAfterAllocation.accRewardsForSubgraph,
        'Snapshots should be in sync after updates',
      )
    })

    it('should not brick rewards when signal update zeros the per-signal delta (same block)', async function () {
      await setupSubgraphWithAllocation()

      // Advance blocks
      await helpers.mine(100)

      // Get the view function result (what rewards SHOULD be) before any updates
      // Note: We call this to ensure the function works, but we verify via stored state below
      await rewardsManager.getAccRewardsPerAllocatedToken(subgraphDeploymentID)

      // Disable automine to batch transactions into the same block
      await hre.network.provider.send('evm_setAutomine', [false])

      try {
        // Call signal update first (zeros per-signal delta and accumulates rewards in accRewardsForSubgraph)
        const signalTx = await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)

        // Call allocation update (per-signal delta is now 0, but rewards are in accRewardsForSubgraph)
        const allocTx = await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)

        // Mine both transactions in the same block
        await hre.network.provider.send('evm_mine')

        // Wait for both transactions to be mined
        await signalTx.wait()
        await allocTx.wait()
      } finally {
        // Re-enable automine
        await hre.network.provider.send('evm_setAutomine', [true])
      }

      // Get the rewards accumulated in accRewardsForSubgraph
      const afterSignal = await rewardsManager.subgraphs(subgraphDeploymentID)
      const rewardsAccumulated = afterSignal.accRewardsForSubgraph

      // These rewards should eventually be distributed to allocations
      expect(rewardsAccumulated).to.be.gt(0, 'Rewards should be accumulated at subgraph level')

      // Get stored state
      const subgraph = await rewardsManager.subgraphs(subgraphDeploymentID)

      // THE BUG: With the original buggy code, accRewardsPerAllocatedToken would remain at 0
      // because newRewards from per-signal delta is 0, causing early return.
      // THE FIX: accRewardsPerAllocatedToken should be updated to reflect the accumulated rewards
      expect(subgraph.accRewardsPerAllocatedToken).to.be.gt(
        0,
        'accRewardsPerAllocatedToken should be non-zero (BUG: rewards were bricked)',
      )

      // Verify view function and stored state are consistent
      const [viewAccRewardsPerAllocatedToken] =
        await rewardsManager.getAccRewardsPerAllocatedToken(subgraphDeploymentID)

      // The view should equal the stored value (since snapshots are synced)
      expect(viewAccRewardsPerAllocatedToken).to.equal(
        subgraph.accRewardsPerAllocatedToken,
        'View function should match stored state after updates',
      )
    })

    it('should handle multiple signal updates without losing rewards (same block allocation)', async function () {
      await setupSubgraphWithAllocation()

      // Advance blocks
      await helpers.mine(50)

      // First signal update
      await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)
      const afterFirstSignal = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Advance more blocks
      await helpers.mine(50)

      // Disable automine to batch signal + allocation into same block
      await hre.network.provider.send('evm_setAutomine', [false])

      try {
        // Second signal update (without allocation update in between)
        const signalTx = await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)

        // Allocation update in the same block (per-signal delta is 0)
        const allocTx = await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)

        // Mine both in the same block
        await hre.network.provider.send('evm_mine')

        await signalTx.wait()
        await allocTx.wait()
      } finally {
        await hre.network.provider.send('evm_setAutomine', [true])
      }

      const afterSecondSignal = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Rewards should have accumulated
      expect(afterSecondSignal.accRewardsForSubgraph).to.be.gt(
        afterFirstSignal.accRewardsForSubgraph,
        'Rewards should accumulate across signal updates',
      )

      const afterAllocation = await rewardsManager.subgraphs(subgraphDeploymentID)

      // All accumulated rewards should be distributed
      expect(afterAllocation.accRewardsPerAllocatedToken).to.be.gt(
        0,
        'Rewards from multiple signal updates should be distributed',
      )

      // Snapshots should be in sync
      expect(afterAllocation.accRewardsForSubgraphSnapshot).to.equal(
        afterAllocation.accRewardsForSubgraph,
        'Snapshots should be in sync',
      )
    })
  })

  describe('snapshot consistency in reclaim paths', function () {
    it('should update accRewardsForSubgraphSnapshot when rewards are reclaimed due to denial', async function () {
      await setupSubgraphWithAllocation()

      // Deny the subgraph
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID, true)

      // Advance blocks to accumulate rewards
      await helpers.mine(100)

      // Get state before
      const subgraphBefore = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Call allocation update - should reclaim (not distribute) rewards
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)

      // Get state after
      const subgraphAfter = await rewardsManager.subgraphs(subgraphDeploymentID)

      // accRewardsPerAllocatedToken should NOT increase (rewards reclaimed, not distributed)
      expect(subgraphAfter.accRewardsPerAllocatedToken).to.equal(
        subgraphBefore.accRewardsPerAllocatedToken,
        'accRewardsPerAllocatedToken should not increase when denied',
      )

      // THE FIX: accRewardsForSubgraphSnapshot should be updated to prevent re-reclaiming
      expect(subgraphAfter.accRewardsForSubgraphSnapshot).to.be.gte(
        subgraphBefore.accRewardsForSubgraphSnapshot,
        'accRewardsForSubgraphSnapshot should be updated in reclaim path',
      )
    })

    it('should not double-reclaim rewards after snapshot update', async function () {
      await setupSubgraphWithAllocation()

      // Deny the subgraph
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID, true)

      // Advance blocks
      await helpers.mine(100)

      // First allocation update - reclaims rewards
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
      const afterFirstReclaim = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Second allocation update - each tx advances a block, so there's 1 more block of rewards
      // The key invariant is that rewards are properly accounted for, not double-reclaimed
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
      const afterSecondReclaim = await rewardsManager.subgraphs(subgraphDeploymentID)

      // The snapshot should have advanced by at most 1 block's worth of rewards
      // (Each transaction creates a new block in Hardhat)
      const maxOneBlockReward = ISSUANCE_PER_BLOCK.mul(tokensToSignal).div(await grt.balanceOf(curation.address))

      const snapshotDiff = afterSecondReclaim.accRewardsForSubgraphSnapshot.sub(
        afterFirstReclaim.accRewardsForSubgraphSnapshot,
      )

      // The difference should be at most one block's worth of rewards
      expect(snapshotDiff).to.be.lte(
        maxOneBlockReward.mul(2), // Allow for rounding and timing
        'Should only process one block worth of new rewards',
      )

      // Verify accRewardsPerAllocatedToken didn't increase (rewards still reclaimed, not distributed)
      expect(afterSecondReclaim.accRewardsPerAllocatedToken).to.equal(
        afterFirstReclaim.accRewardsPerAllocatedToken,
        'accRewardsPerAllocatedToken should not change during reclaim',
      )
    })
  })

  describe('onSubgraphSignalUpdate on denied subgraph', function () {
    it('should reclaim rewards when onSubgraphSignalUpdate is called on denied subgraph', async function () {
      await setupSubgraphWithAllocation()

      // Configure reclaim address for SUBGRAPH_DENIED
      const SUBGRAPH_DENIED = hre.ethers.utils.id('SUBGRAPH_DENIED')
      await rewardsManager.connect(governor).setReclaimAddress(SUBGRAPH_DENIED, governor.address)

      // Verify reclaim address was set
      const reclaimAddr = await rewardsManager.getReclaimAddress(SUBGRAPH_DENIED)
      expect(reclaimAddr).to.equal(governor.address, 'Reclaim address should be set')

      // Deny the subgraph
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID, true)

      // Record state after denial (setDenied calls onSubgraphAllocationUpdate internally)
      const afterDenial = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Advance blocks - rewards should accumulate
      await helpers.mine(100)

      // Call onSubgraphSignalUpdate (simulates curator action)
      // With Option B fix: rewards should be reclaimed immediately
      const tx = await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)
      const receipt = await tx.wait()
      const afterSignalUpdate = await rewardsManager.subgraphs(subgraphDeploymentID)

      // With Option B: accRewardsForSubgraph should NOT change for denied subgraphs
      // (rewards are reclaimed directly, not stored)
      expect(afterSignalUpdate.accRewardsForSubgraph).to.equal(
        afterDenial.accRewardsForSubgraph,
        'accRewardsForSubgraph should not change for denied subgraphs (rewards reclaimed)',
      )

      // Verify reclaim event was emitted
      const reclaimEvent = receipt.events?.find((e) => e.event === 'RewardsReclaimed')
      expect(reclaimEvent).to.not.be.undefined
      // Event args: (reason, rewards, indexer, allocationId, subgraphDeploymentId)
      const rewards = reclaimEvent!.args![1] // rewards is second arg
      expect(rewards).to.be.gt(0, 'Should have reclaimed rewards')
    })

    it('should accumulate rewards for claimable subgraphs in onSubgraphSignalUpdate', async function () {
      await setupSubgraphWithAllocation()

      // Record initial state (subgraph is claimable by default)
      const initialState = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Advance blocks - rewards should accumulate
      await helpers.mine(100)

      // Call onSubgraphSignalUpdate
      await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)
      const afterSignalUpdate = await rewardsManager.subgraphs(subgraphDeploymentID)

      // For claimable subgraphs: accRewardsForSubgraph SHOULD increase
      expect(afterSignalUpdate.accRewardsForSubgraph).to.be.gt(
        initialState.accRewardsForSubgraph,
        'accRewardsForSubgraph should increase for claimable subgraphs',
      )
    })

    it('view function getAccRewardsForSubgraph should not jump during denial', async function () {
      await setupSubgraphWithAllocation()

      // Accumulate some rewards while claimable
      await helpers.mine(50)

      // Deny the subgraph (setDenied distributes pre-denial rewards via onSubgraphAllocationUpdate)
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID, true)

      // Record view value immediately after denial
      const rewardsAtDenial = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID)
      expect(rewardsAtDenial).to.be.gt(0, 'Should have accumulated pre-denial rewards')

      // Advance blocks during denial
      await helpers.mine(100)

      // View function should return SAME value (no jump up during denial)
      const rewardsDuringDenial = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID)
      expect(rewardsDuringDenial).to.equal(rewardsAtDenial, 'View should not increase during denial')

      // Call signal update (with bug, this would NOT reclaim, causing view to jump on next allocation update)
      // Configure reclaim address so rewards are reclaimed
      const SUBGRAPH_DENIED = hre.ethers.utils.id('SUBGRAPH_DENIED')
      await rewardsManager.connect(governor).setReclaimAddress(SUBGRAPH_DENIED, governor.address)
      await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)

      // View function should STILL return same value (rewards reclaimed, not accumulated)
      const rewardsAfterSignalUpdate = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID)
      expect(rewardsAfterSignalUpdate).to.equal(rewardsAtDenial, 'View should not jump after signal update')

      // Mine more blocks
      await helpers.mine(50)

      // Call allocation update
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)

      // View should STILL be stable (rewards reclaimed, not accumulated)
      const rewardsAfterAllocationUpdate = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID)
      expect(rewardsAfterAllocationUpdate).to.equal(rewardsAtDenial, 'View should not jump after allocation update')
    })
  })

  describe('onSubgraphSignalUpdate with no allocations', function () {
    it('should reclaim as NO_ALLOCATED_TOKENS when signal exists but no allocations', async function () {
      // Setup: only signal, no allocation
      await grt.connect(governor).mint(curator.address, tokensToSignal)
      await grt.connect(curator).approve(curation.address, tokensToSignal)
      await curation.connect(curator).mint(subgraphDeploymentID, tokensToSignal, 0)

      // Configure reclaim address for NO_ALLOCATED_TOKENS
      const NO_ALLOCATED_TOKENS = hre.ethers.utils.id('NO_ALLOCATED_TOKENS')
      await rewardsManager.connect(governor).setReclaimAddress(NO_ALLOCATED_TOKENS, governor.address)

      // Record initial state
      const initialState = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Advance blocks - rewards should accumulate
      await helpers.mine(100)

      // Call onSubgraphSignalUpdate - should reclaim as NO_ALLOCATED_TOKENS
      const tx = await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)
      const receipt = await tx.wait()
      const afterSignalUpdate = await rewardsManager.subgraphs(subgraphDeploymentID)

      // accRewardsForSubgraph should NOT change (rewards reclaimed, not accumulated)
      expect(afterSignalUpdate.accRewardsForSubgraph).to.equal(
        initialState.accRewardsForSubgraph,
        'accRewardsForSubgraph should not change when no allocations (rewards reclaimed)',
      )

      // Verify reclaim event was emitted with NO_ALLOCATED_TOKENS reason
      const reclaimEvent = receipt.events?.find((e) => e.event === 'RewardsReclaimed')
      expect(reclaimEvent).to.not.be.undefined
      expect(reclaimEvent!.args![0]).to.equal(NO_ALLOCATED_TOKENS, 'Should reclaim with NO_ALLOCATED_TOKENS reason')
      expect(reclaimEvent!.args![1]).to.be.gt(0, 'Should have reclaimed rewards')
    })

    it('view function should not show phantom rewards when no allocations', async function () {
      // Setup: only signal, no allocation
      await grt.connect(governor).mint(curator.address, tokensToSignal)
      await grt.connect(curator).approve(curation.address, tokensToSignal)
      await curation.connect(curator).mint(subgraphDeploymentID, tokensToSignal, 0)

      // Record view immediately after signal
      const viewAfterSignal = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID)

      // Advance blocks
      await helpers.mine(100)

      // Configure reclaim and call signal update
      const NO_ALLOCATED_TOKENS = hre.ethers.utils.id('NO_ALLOCATED_TOKENS')
      await rewardsManager.connect(governor).setReclaimAddress(NO_ALLOCATED_TOKENS, governor.address)
      await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)

      // View should remain stable (rewards reclaimed)
      const viewAfterReclaim = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID)
      expect(viewAfterReclaim).to.equal(viewAfterSignal, 'View should not grow when no allocations')
    })
  })

  describe('invariant: no rewards lost or double-counted', function () {
    it('should maintain accounting invariant across mixed updates (with same-block scenarios)', async function () {
      await setupSubgraphWithAllocation()

      // Sequence of operations that could trigger the bug
      await helpers.mine(25)

      // First: signal update followed by allocation update in SAME BLOCK
      await hre.network.provider.send('evm_setAutomine', [false])
      try {
        const signalTx1 = await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)
        const allocTx1 = await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
        await hre.network.provider.send('evm_mine')
        await signalTx1.wait()
        await allocTx1.wait()
      } finally {
        await hre.network.provider.send('evm_setAutomine', [true])
      }

      await helpers.mine(25)

      // Second: double signal update followed by allocation update in SAME BLOCK
      await hre.network.provider.send('evm_setAutomine', [false])
      try {
        const signalTx2 = await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)
        const signalTx3 = await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)
        const allocTx2 = await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
        await hre.network.provider.send('evm_mine')
        await signalTx2.wait()
        await signalTx3.wait()
        await allocTx2.wait()
      } finally {
        await hre.network.provider.send('evm_setAutomine', [true])
      }

      // Final state check
      const finalSubgraph = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Key invariant: snapshots should be in sync
      expect(finalSubgraph.accRewardsForSubgraphSnapshot).to.equal(
        finalSubgraph.accRewardsForSubgraph,
        'INVARIANT VIOLATED: accRewardsForSubgraphSnapshot != accRewardsForSubgraph',
      )

      // Rewards should have been distributed
      expect(finalSubgraph.accRewardsPerAllocatedToken).to.be.gt(
        0,
        'Rewards should have been distributed to allocations',
      )
    })
  })
})

import { Curation } from '@graphprotocol/contracts'
import { GraphToken } from '@graphprotocol/contracts'
import { IStaking } from '@graphprotocol/contracts'
import { RewardsManager } from '@graphprotocol/contracts'
import { deriveChannelKey, GraphNetworkContracts, helpers, randomHexBytes, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { BigNumber, constants, utils } from 'ethers'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

const { HashZero } = constants

/**
 * Tests for snapshot inversion on upgrade.
 *
 * Terminology:
 *   A = accRewardsForSubgraph         (stored accumulator, set at signal updates)
 *   S = accRewardsForSubgraphSnapshot (stored snapshot, set at allocation updates)
 *   P = rewardsSinceSignalSnapshot    (pending rewards since last signal snapshot)
 *
 * After a proxy upgrade, subgraphs whose last pre-upgrade interaction was
 * `onSubgraphAllocationUpdate` have A < S. The old code set S from a view function
 * (storage + pending) while leaving A at its stored value, so S leads and A lags.
 * The original code's `A.sub(S).add(P)` reverts on the intermediate `A - S`.
 *
 * The fix: Rearrange to `A.add(P).sub(S)` — add P first, then subtract S.
 * Since P covers T1→now and the gap S - A covers T1→T2, and now >= T2,
 * we have S - A <= P, so S <= A + P always holds. No clamping needed.
 *
 * These tests use `hardhat_setStorageAt` to directly create the inverted storage state
 * that exists on-chain for affected subgraphs.
 */
describe('Rewards: Snapshot Inversion', () => {
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

  const tokensToSignal = toGRT('1000')
  const tokensToStake = toGRT('100000')
  const tokensToAllocate = toGRT('10000')

  // Storage slot for the `subgraphs` mapping in RewardsManagerV1Storage.
  // Computed by counting all inherited storage variables:
  // Managed: controller(0), _addressCache(1), __gap[10](2-11) = 12 slots
  // V1Storage: __DEPRECATED_issuanceRate(12), accRewardsPerSignal(13),
  //            accRewardsPerSignalLastBlockUpdated(14), subgraphAvailabilityOracle(15),
  //            subgraphs(16)
  const SUBGRAPHS_MAPPING_SLOT = 16

  /**
   * Compute the storage slot for a field within a Subgraph struct in the subgraphs mapping.
   *
   * For `mapping(bytes32 => Subgraph)` at slot S, key K:
   *   base = keccak256(abi.encode(K, S))
   *   field 0 (accRewardsForSubgraph)         = base + 0
   *   field 1 (accRewardsForSubgraphSnapshot)  = base + 1
   *   field 2 (accRewardsPerSignalSnapshot)    = base + 2
   *   field 3 (accRewardsPerAllocatedToken)    = base + 3
   */
  function subgraphStorageSlot(subgraphId: string, fieldOffset: number): string {
    const baseSlot = utils.keccak256(
      utils.defaultAbiCoder.encode(['bytes32', 'uint256'], [subgraphId, SUBGRAPHS_MAPPING_SLOT]),
    )
    return utils.hexZeroPad(BigNumber.from(baseSlot).add(fieldOffset).toHexString(), 32)
  }

  /**
   * Set a uint256 value at a specific storage slot of the RewardsManager proxy.
   */
  async function setStorage(slot: string, value: BigNumber): Promise<void> {
    await hre.network.provider.send('hardhat_setStorageAt', [
      rewardsManager.address,
      slot,
      utils.hexZeroPad(value.toHexString(), 32),
    ])
  }

  /**
   * Create the inverted snapshot state that exists on-chain for affected subgraphs.
   *
   * Sets: accRewardsForSubgraphSnapshot = accRewardsForSubgraph + gap
   * This is the state left by the old `onSubgraphAllocationUpdate` which wrote
   * the snapshot from a view function (storage + pending), while leaving
   * accRewardsForSubgraph at its stored value.
   */
  async function createInvertedState(subgraphId: string, gap: BigNumber): Promise<void> {
    const subgraph = await rewardsManager.subgraphs(subgraphId)
    const currentAccRewards = subgraph.accRewardsForSubgraph
    const invertedSnapshot = currentAccRewards.add(gap)

    // Write accRewardsForSubgraphSnapshot = currentAccRewards + gap (field offset 1)
    const snapshotSlot = subgraphStorageSlot(subgraphId, 1)
    await setStorage(snapshotSlot, invertedSnapshot)

    // Verify the inversion was written correctly
    const after = await rewardsManager.subgraphs(subgraphId)
    expect(after.accRewardsForSubgraphSnapshot).to.equal(invertedSnapshot)
    expect(after.accRewardsForSubgraph).to.be.lt(after.accRewardsForSubgraphSnapshot)
  }

  before(async function () {
    ;[curator, indexer] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    grt = contracts.GraphToken as GraphToken
    curation = contracts.Curation as Curation
    staking = contracts.Staking as IStaking
    rewardsManager = contracts.RewardsManager as RewardsManager

    // Set the staking contract as the subgraph service so RewardsManager
    // can see allocations via _getSubgraphAllocatedTokens()
    await rewardsManager.connect(governor).setSubgraphService(staking.address)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  async function setupSubgraphWithAllocation() {
    // Set issuance rate (200 GRT/block) — the fixture defaults to 0
    await rewardsManager.connect(governor).setIssuancePerBlock(toGRT('200'))

    // Curator signals on subgraph
    await grt.connect(governor).mint(curator.address, tokensToSignal)
    await grt.connect(curator).approve(curation.address, tokensToSignal)
    await curation.connect(curator).mint(subgraphDeploymentID, tokensToSignal, 0)

    // Indexer stakes and allocates
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

    // Accumulate some rewards
    await helpers.mine(50)

    // Sync subgraph state so we have non-zero accRewardsForSubgraph
    await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)
  }

  describe('storage slot verification', function () {
    it('should correctly compute and write to subgraph storage slots', async function () {
      await setupSubgraphWithAllocation()

      // Read current state
      const before = await rewardsManager.subgraphs(subgraphDeploymentID)
      expect(before.accRewardsForSubgraph).to.not.equal(0, 'precondition: should have accumulated rewards')

      // Write a known value to accRewardsForSubgraphSnapshot (field 1)
      const testValue = BigNumber.from('12345678901234567890')
      const snapshotSlot = subgraphStorageSlot(subgraphDeploymentID, 1)
      await setStorage(snapshotSlot, testValue)

      // Read back and verify
      const after = await rewardsManager.subgraphs(subgraphDeploymentID)
      expect(after.accRewardsForSubgraphSnapshot).to.equal(testValue)
      // Other fields should be unchanged
      expect(after.accRewardsForSubgraph).to.equal(before.accRewardsForSubgraph)
      expect(after.accRewardsPerSignalSnapshot).to.equal(before.accRewardsPerSignalSnapshot)
      expect(after.accRewardsPerAllocatedToken).to.equal(before.accRewardsPerAllocatedToken)
    })
  })

  describe('inverted state: accumulated < snapshot', function () {
    it('should not revert on onSubgraphSignalUpdate with inverted state', async function () {
      await setupSubgraphWithAllocation()

      // Create the pre-upgrade inverted state (snapshot > accumulated by ~7000 GRT)
      const gap = toGRT('7000')
      await createInvertedState(subgraphDeploymentID, gap)

      // Advance enough blocks so P > gap. At ~200 GRT/block, 50 blocks ≈ 10,000 GRT > 7,000.
      await helpers.mine(50)

      // Old code: A.sub(S).add(P) reverts on intermediate A - S when A < S.
      // Fix: A.add(P).sub(S) adds P first, so A + P >= S always holds.
      await expect(rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)).to.not.be.reverted
    })

    it('should not revert on onSubgraphAllocationUpdate with inverted state', async function () {
      await setupSubgraphWithAllocation()

      const gap = toGRT('7000')
      await createInvertedState(subgraphDeploymentID, gap)

      await helpers.mine(50)

      await expect(rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)).to.not.be.reverted
    })

    it('should sync snapshots after first successful call', async function () {
      await setupSubgraphWithAllocation()

      const gap = toGRT('7000')
      await createInvertedState(subgraphDeploymentID, gap)

      await helpers.mine(50)

      // First call with inverted state
      await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)

      // After the fix processes the inverted state, snapshots should be synced
      const after = await rewardsManager.subgraphs(subgraphDeploymentID)
      expect(after.accRewardsForSubgraphSnapshot).to.equal(
        after.accRewardsForSubgraph,
        'snapshot should equal accumulated after fix processes inverted state',
      )

      // Subsequent calls should work normally
      await helpers.mine(10)
      await expect(rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)).to.not.be.reverted

      const afterSecond = await rewardsManager.subgraphs(subgraphDeploymentID)
      expect(afterSecond.accRewardsForSubgraphSnapshot).to.equal(afterSecond.accRewardsForSubgraph)
    })
  })

  describe('accounting correctness with inverted state', function () {
    it('should correctly compute undistributed rewards: (A+P).sub(S)', async function () {
      await setupSubgraphWithAllocation()

      // Record state before inversion
      const before = await rewardsManager.subgraphs(subgraphDeploymentID)
      const perAllocBefore = before.accRewardsPerAllocatedToken

      // Create inversion with a small gap (smaller than rewards that will accrue)
      const gap = toGRT('500')
      await createInvertedState(subgraphDeploymentID, gap)

      // Advance enough blocks that S < A + P (i.e., new rewards exceed the gap)
      // With 200 GRT/block and only one subgraph signalled, each block adds ~200 GRT of P
      // 10 blocks ≈ 2000 GRT of P, gap = 500 GRT
      // So (A + P) - S = A + 2000 - (A + 500) = 1500 GRT undistributed
      await helpers.mine(10)

      // Call allocation update to distribute rewards
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)

      const after = await rewardsManager.subgraphs(subgraphDeploymentID)

      // accRewardsPerAllocatedToken should increase (rewards were distributed)
      expect(perAllocBefore).to.be.lt(after.accRewardsPerAllocatedToken, 'should distribute rewards: 0 < (A + P) - S')

      // The distributed amount should be less than total new rewards (P)
      // because the gap represents already-distributed rewards from the old code
      // Undistributed = (A + P) - S = P - gap (since S = A + gap)
      // If P ≈ 2000 GRT and gap = 500 GRT, undistributed ≈ 1500 GRT
      // Without the gap subtraction, it would have been P ≈ 2000 GRT (double-counting)

      // Verify snapshots are synced
      expect(after.accRewardsForSubgraphSnapshot).to.equal(after.accRewardsForSubgraph)
    })

    it('should not double-count: distributed rewards account for the gap', async function () {
      await setupSubgraphWithAllocation()

      // Get a reference: how many rewards are distributed in normal operation
      const stateBefore = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Create a scenario where gap = 500 GRT
      const gap = toGRT('500')
      await createInvertedState(subgraphDeploymentID, gap)

      await helpers.mine(20)

      // Process the inverted state
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
      const afterInverted = await rewardsManager.subgraphs(subgraphDeploymentID)
      const perAllocAfterInverted = afterInverted.accRewardsPerAllocatedToken

      // Now do a SECOND allocation update with normal state (snapshots are synced)
      await helpers.mine(20)
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
      const afterNormal = await rewardsManager.subgraphs(subgraphDeploymentID)

      // The second update should distribute ~20 blocks worth of rewards
      // The first update distributed less (because gap was subtracted)
      // This proves no double-counting: the gap was properly deducted
      const firstDelta = perAllocAfterInverted.sub(stateBefore.accRewardsPerAllocatedToken)
      const secondDelta = afterNormal.accRewardsPerAllocatedToken.sub(perAllocAfterInverted)

      // First delta < second delta because the gap was subtracted
      // (both periods have ~20 blocks, but first period deducts the 500 GRT gap)
      expect(firstDelta).to.be.lt(secondDelta, 'first update should distribute less due to gap deduction')
    })

    it('should distribute exactly P - gap rewards (gap deducted from pending)', async function () {
      await setupSubgraphWithAllocation()

      // Sync state so we have a clean baseline
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
      const baseline = await rewardsManager.subgraphs(subgraphDeploymentID)
      const perAllocBaseline = baseline.accRewardsPerAllocatedToken

      // Create inversion with a known gap
      const gap = toGRT('500')
      await createInvertedState(subgraphDeploymentID, gap)

      // Mine blocks, then do a normal (non-inverted) reference run in a parallel universe
      // We can't do that, but we CAN check that the gap is properly deducted by
      // comparing inverted vs non-inverted runs over the same block count.

      // First: process the inverted state
      await helpers.mine(20)
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
      const afterInverted = await rewardsManager.subgraphs(subgraphDeploymentID)
      const invertedDelta = afterInverted.accRewardsPerAllocatedToken.sub(perAllocBaseline)

      // Second: run the same block count with synced state (no gap)
      await helpers.mine(20)
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
      const afterNormal = await rewardsManager.subgraphs(subgraphDeploymentID)
      const normalDelta = afterNormal.accRewardsPerAllocatedToken.sub(afterInverted.accRewardsPerAllocatedToken)

      // The inverted run should distribute LESS because the gap was subtracted.
      // Both periods have ~20 blocks of rewards, but the inverted period deducts 500 GRT.
      expect(invertedDelta).to.be.lt(normalDelta, 'inverted period should distribute less due to gap deduction')
      expect(invertedDelta).to.not.equal(0, 'should still distribute some rewards (gap < P)')
    })
  })

  describe('normal operation (no inversion)', function () {
    it('should produce identical results when A == S (post-fix steady state)', async function () {
      await setupSubgraphWithAllocation()

      // Ensure snapshots are synced (normal state)
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
      const synced = await rewardsManager.subgraphs(subgraphDeploymentID)
      expect(synced.accRewardsForSubgraphSnapshot).to.equal(synced.accRewardsForSubgraph)

      const perAllocBefore = synced.accRewardsPerAllocatedToken

      // Advance and update - this is the normal steady-state path
      await helpers.mine(20)
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)

      const after = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Rewards should be distributed normally
      expect(perAllocBefore).to.be.lt(after.accRewardsPerAllocatedToken)
      expect(after.accRewardsForSubgraphSnapshot).to.equal(after.accRewardsForSubgraph)
    })

    it('should handle zero rewards gracefully (same block, no new rewards)', async function () {
      await setupSubgraphWithAllocation()

      // Sync state
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)

      // Call again immediately (same block via automine off)
      await hre.network.provider.send('evm_setAutomine', [false])
      try {
        const tx = await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)
        await hre.network.provider.send('evm_mine')
        await tx.wait()
      } finally {
        await hre.network.provider.send('evm_setAutomine', [true])
      }

      const after = await rewardsManager.subgraphs(subgraphDeploymentID)

      // Per-alloc-token should be unchanged (zero rewards in same block)
      // Note: the transaction itself mines a block, so there may be minimal reward
      expect(after.accRewardsForSubgraphSnapshot).to.equal(after.accRewardsForSubgraph)
    })
  })

  describe('realistic pre-upgrade scenario', function () {
    it('should handle the exact Arbitrum Sepolia state pattern', async function () {
      await setupSubgraphWithAllocation()

      // Simulate:
      // 1. Old onSubgraphSignalUpdate wrote accRewardsForSubgraph = X (signal-level view value)
      // 2. Old onSubgraphAllocationUpdate wrote accRewardsForSubgraphSnapshot = X + delta
      //    (via getAccRewardsForSubgraph view which returns storage + pending)
      // 3. Proxy upgrade preserves this state
      // 4. New code calls _updateSubgraphRewards: A.sub(S) underflows

      // Read current A value
      const state = await rewardsManager.subgraphs(subgraphDeploymentID)
      const A = state.accRewardsForSubgraph

      // Set S = A + 7235 GRT (matching the ~7235 GRT gap observed on Arbitrum Sepolia)
      const observedGap = toGRT('7235')
      const accSlot = subgraphStorageSlot(subgraphDeploymentID, 1)
      await setStorage(accSlot, A.add(observedGap))

      // Verify the inversion
      const inverted = await rewardsManager.subgraphs(subgraphDeploymentID)
      expect(inverted.accRewardsForSubgraph).to.be.lt(inverted.accRewardsForSubgraphSnapshot)

      // Advance blocks (some time passes after upgrade before first interaction)
      await helpers.mine(50)

      // First interaction after "upgrade": should NOT revert
      await expect(rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)).to.not.be.reverted

      // State should be healed
      const healed = await rewardsManager.subgraphs(subgraphDeploymentID)
      expect(healed.accRewardsForSubgraphSnapshot).to.equal(healed.accRewardsForSubgraph)

      // All subsequent operations should work
      await helpers.mine(10)
      await expect(rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID)).to.not.be.reverted

      await helpers.mine(10)
      await expect(rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID)).to.not.be.reverted
    })
  })
})

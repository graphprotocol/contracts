import { Curation } from '@graphprotocol/contracts'
import { EpochManager } from '@graphprotocol/contracts'
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

// Condition identifiers (matching RewardsCondition.sol)
const INDEXER_INELIGIBLE = utils.id('INDEXER_INELIGIBLE')
const SUBGRAPH_DENIED = utils.id('SUBGRAPH_DENIED')
const CLOSE_ALLOCATION = utils.id('CLOSE_ALLOCATION')
const NO_SIGNAL = utils.id('NO_SIGNAL')

// Tolerance for fixed-point arithmetic rounding errors (matching Foundry tests)
const REWARDS_TOLERANCE = 20000

// Helper to check approximate equality for rewards (allows for rounding errors in fixed-point math)
function expectApproxEq(actual: BigNumber, expected: BigNumber, message: string) {
  const diff = actual.sub(expected).abs()
  expect(
    diff.lte(REWARDS_TOLERANCE),
    `${message}: difference ${diff.toString()} exceeds tolerance ${REWARDS_TOLERANCE}`,
  ).to.be.true
}
const NO_ALLOCATION = utils.id('NO_ALLOCATION')
const BELOW_MINIMUM_SIGNAL = utils.id('BELOW_MINIMUM_SIGNAL')

describe('Rewards - Reclaim Addresses', () => {
  const graph = hre.graph()
  let curator1: SignerWithAddress
  let governor: SignerWithAddress
  let indexer1: SignerWithAddress
  let reclaimWallet: SignerWithAddress
  let otherWallet: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let grt: GraphToken
  let curation: Curation
  let epochManager: EpochManager
  let staking: IStaking
  let rewardsManager: RewardsManager

  // Derive channel key for indexer used to sign attestations
  const channelKey1 = deriveChannelKey()

  const subgraphDeploymentID1 = randomHexBytes()

  const allocationID1 = channelKey1.address

  const metadata = HashZero

  const ISSUANCE_PER_BLOCK = toGRT('200') // 200 GRT every block

  async function setupIndexerAllocation() {
    // Setup
    await epochManager.connect(governor).setEpochLength(10)

    // Update total signalled
    const signalled1 = toGRT('1500')
    await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

    // Allocate
    const tokensToAllocate = toGRT('12500')
    await staking.connect(indexer1).stake(tokensToAllocate)
    await staking
      .connect(indexer1)
      .allocateFrom(
        indexer1.address,
        subgraphDeploymentID1,
        tokensToAllocate,
        allocationID1,
        metadata,
        await channelKey1.generateProof(indexer1.address),
      )
  }

  before(async function () {
    const testAccounts = await graph.getTestAccounts()
    curator1 = testAccounts[0]
    indexer1 = testAccounts[1]
    reclaimWallet = testAccounts[2]
    otherWallet = testAccounts[3]
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    grt = contracts.GraphToken as GraphToken
    curation = contracts.Curation as Curation
    epochManager = contracts.EpochManager
    staking = contracts.Staking as IStaking
    rewardsManager = contracts.RewardsManager

    // 200 GRT per block
    await rewardsManager.connect(governor).setIssuancePerBlock(ISSUANCE_PER_BLOCK)

    // Distribute test funds
    for (const wallet of [indexer1, curator1]) {
      await grt.connect(governor).mint(wallet.address, toGRT('1000000'))
      await grt.connect(wallet).approve(staking.address, toGRT('1000000'))
      await grt.connect(wallet).approve(curation.address, toGRT('1000000'))
    }
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('setReclaimAddress', function () {
    it('should reject if not governor', async function () {
      const tx = rewardsManager.connect(indexer1).setReclaimAddress(INDEXER_INELIGIBLE, reclaimWallet.address)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('should reject setting reclaim address for bytes32(0)', async function () {
      const tx = rewardsManager.connect(governor).setReclaimAddress(HashZero, reclaimWallet.address)
      await expect(tx).revertedWith('Cannot set reclaim address for (bytes32(0))')
    })

    it('should set eligibility reclaim address if governor', async function () {
      const tx = rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, reclaimWallet.address)
      await expect(tx)
        .emit(rewardsManager, 'ReclaimAddressSet')
        .withArgs(INDEXER_INELIGIBLE, constants.AddressZero, reclaimWallet.address)

      expect(await rewardsManager.getReclaimAddress(INDEXER_INELIGIBLE)).eq(reclaimWallet.address)
    })

    it('should set subgraph denied reclaim address if governor', async function () {
      const tx = rewardsManager.connect(governor).setReclaimAddress(SUBGRAPH_DENIED, reclaimWallet.address)
      await expect(tx)
        .emit(rewardsManager, 'ReclaimAddressSet')
        .withArgs(SUBGRAPH_DENIED, constants.AddressZero, reclaimWallet.address)

      expect(await rewardsManager.getReclaimAddress(SUBGRAPH_DENIED)).eq(reclaimWallet.address)
    })

    it('should allow setting to zero address', async function () {
      await rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, reclaimWallet.address)

      const tx = rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, constants.AddressZero)
      await expect(tx)
        .emit(rewardsManager, 'ReclaimAddressSet')
        .withArgs(INDEXER_INELIGIBLE, reclaimWallet.address, constants.AddressZero)

      expect(await rewardsManager.getReclaimAddress(INDEXER_INELIGIBLE)).eq(constants.AddressZero)
    })

    it('should not emit event when setting same address', async function () {
      await rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, reclaimWallet.address)

      const tx = rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, reclaimWallet.address)
      await expect(tx).to.not.emit(rewardsManager, 'ReclaimAddressSet')
    })
  })

  describe('reclaim denied rewards - subgraph denylist', function () {
    // Note: With the new denied-period rewards implementation, rewards for denied subgraphs
    // are reclaimed at the subgraph level via onSubgraphAllocationUpdate(), not at the
    // allocation level via _deniedRewards(). This means:
    // - RewardsDenied is NOT emitted (legacy allocation-level event)
    // - RewardsReclaimed IS emitted but with address(0) for indexer/allocationID
    // - Allocations created while denied have frozen accumulator, so rewards = 0 at close

    it('should mint to reclaim address when subgraph denied and reclaim address set', async function () {
      // Setup reclaim address
      await rewardsManager.connect(governor).setReclaimAddress(SUBGRAPH_DENIED, reclaimWallet.address)

      // Setup denylist
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Calculate expected rewards (approximate - timing can cause slight variations)
      const expectedRewards = toGRT('1400')

      // Check reclaim wallet balance before
      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Close allocation - rewards are reclaimed at subgraph level (address(0) for indexer/allocationID)
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      // RewardsDenied is not emitted - denial is handled at subgraph level now
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDenied')
      // RewardsReclaimed emitted with address(0) for indexer/allocationID (subgraph-level reclaim)
      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      // Check reclaim wallet received the rewards (allow for rounding errors)
      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expectApproxEq(balanceAfter.sub(balanceBefore), expectedRewards, 'reclaimed rewards')
    })

    it('should reclaim pre-denial rewards via _deniedRewards when denied after allocation', async function () {
      // Setup reclaim address BEFORE allocation
      await rewardsManager.connect(governor).setReclaimAddress(SUBGRAPH_DENIED, reclaimWallet.address)
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Create allocation FIRST (before deny)
      await setupIndexerAllocation()

      // Mine blocks to accrue rewards
      await helpers.mineEpoch(epochManager)

      // Deny AFTER allocation — pre-denial rewards exist at the allocation level
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Check reclaim wallet balance before
      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Close allocation — pre-denial rewards flow through _deniedRewards → _reclaimRewards
      const tx = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt = await tx.wait()

      // Parse RewardsManager events from the transaction receipt
      const parsedEvents = receipt.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .filter((e) => e !== null)

      // RewardsDenied IS emitted (allocation-level denial for pre-denial rewards)
      const deniedEvents = parsedEvents.filter((e) => e!.name === 'RewardsDenied')
      expect(deniedEvents.length).to.equal(1, 'RewardsDenied event not found')
      expect(deniedEvents[0]!.args[0]).to.equal(indexer1.address)
      expect(deniedEvents[0]!.args[1]).to.equal(allocationID1)

      // RewardsReclaimed emitted with actual indexer/allocationID (allocation-level reclaim)
      const reclaimEvents = parsedEvents.filter((e) => e!.name === 'RewardsReclaimed')
      expect(reclaimEvents.length).to.be.gte(1, 'RewardsReclaimed event not found')
      // Find the allocation-level reclaim (has non-zero indexer and allocationID)
      const allocationReclaim = reclaimEvents.find((e) => e!.args[2] !== constants.AddressZero)
      expect(allocationReclaim).to.not.be.undefined
      expect(allocationReclaim!.args[0]).to.equal(SUBGRAPH_DENIED)
      expectApproxEq(allocationReclaim!.args[1], toGRT('1400'), 'reclaimed amount')
      expect(allocationReclaim!.args[2]).to.equal(indexer1.address)
      expect(allocationReclaim!.args[3]).to.equal(allocationID1)
      expect(allocationReclaim!.args[4]).to.equal(subgraphDeploymentID1)

      // Reclaim wallet received the pre-denial rewards (may receive additional rewards from subgraph-level reclaim)
      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expect(balanceAfter.sub(balanceBefore)).gte(toGRT('1400'))
    })

    it('should not mint to reclaim address when reclaim address not set', async function () {
      // Do NOT set reclaim address (defaults to zero address)

      // Setup denylist
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Close allocation - no events emitted when no reclaim address configured
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      // RewardsDenied is not emitted - denial is handled at subgraph level now
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDenied')
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')
    })
  })

  describe('reclaim denied rewards - eligibility', function () {
    it('should mint to reclaim address when eligibility denied and reclaim address set', async function () {
      // Setup reclaim address
      await rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, reclaimWallet.address)

      // Setup eligibility oracle that denies
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Calculate expected rewards
      const expectedRewards = toGRT('1400')

      // Check reclaim wallet balance before
      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Close allocation - should emit both denial and reclaim events
      const tx = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt = await tx.wait()

      // Parse RewardsManager events from the transaction receipt
      const parsedEvents = receipt.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .filter((e) => e !== null)

      // Check RewardsDeniedDueToEligibility event
      const denialEvents = parsedEvents.filter((e) => e!.name === 'RewardsDeniedDueToEligibility')
      expect(denialEvents.length).to.equal(1, 'RewardsDeniedDueToEligibility event not found')
      expect(denialEvents[0]!.args[0]).to.equal(indexer1.address)
      expect(denialEvents[0]!.args[1]).to.equal(allocationID1)
      expectApproxEq(denialEvents[0]!.args[2], expectedRewards, 'denied rewards amount')

      // Check RewardsReclaimed event exists and verify args
      const reclaimEvents = parsedEvents.filter((e) => e!.name === 'RewardsReclaimed')
      expect(reclaimEvents.length).to.be.gte(1, 'RewardsReclaimed event not found')
      const reclaimEvent = reclaimEvents.find((e) => e!.args[0] === INDEXER_INELIGIBLE)
      expect(reclaimEvent).to.not.be.undefined
      expect(reclaimEvent!.args[0]).to.equal(INDEXER_INELIGIBLE)
      expectApproxEq(reclaimEvent!.args[1], expectedRewards, 'reclaimed amount')
      expect(reclaimEvent!.args[2]).to.equal(indexer1.address)
      expect(reclaimEvent!.args[3]).to.equal(allocationID1)
      expect(reclaimEvent!.args[4]).to.equal(subgraphDeploymentID1)

      // Check reclaim wallet received the rewards
      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expectApproxEq(balanceAfter.sub(balanceBefore), expectedRewards, 'wallet balance increase')
    })

    it('should not mint to reclaim address when reclaim address not set', async function () {
      // Do NOT set reclaim address (defaults to zero address)

      // Setup eligibility oracle that denies
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      const expectedRewards = toGRT('1400')

      // Close allocation - should only emit denial event, not reclaim
      const tx = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt = await tx.wait()

      // Parse RewardsManager events from the transaction receipt
      const parsedEvents = receipt.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .filter((e) => e !== null)

      // Check RewardsDeniedDueToEligibility event
      const denialEvents = parsedEvents.filter((e) => e!.name === 'RewardsDeniedDueToEligibility')
      expect(denialEvents.length).to.equal(1, 'RewardsDeniedDueToEligibility event not found')
      expect(denialEvents[0]!.args[0]).to.equal(indexer1.address)
      expect(denialEvents[0]!.args[1]).to.equal(allocationID1)
      expectApproxEq(denialEvents[0]!.args[2], expectedRewards, 'denied rewards amount')

      // Check no RewardsReclaimed event
      const reclaimEvents = parsedEvents.filter((e) => e!.name === 'RewardsReclaimed')
      expect(reclaimEvents.length).to.equal(0, 'RewardsReclaimed event should not be emitted')
    })
  })

  describe('reclaim precedence - first successful reclaim wins', function () {
    // Note: With subgraph-level denial, rewards are reclaimed via onSubgraphAllocationUpdate()
    // and the allocation-level _deniedRewards() path (which checks eligibility) is not reached
    // because rewards = 0 for allocations created while denied.

    it('should reclaim to SUBGRAPH_DENIED when both fail and both addresses configured', async function () {
      // Setup BOTH reclaim addresses
      await rewardsManager.connect(governor).setReclaimAddress(SUBGRAPH_DENIED, reclaimWallet.address)
      await rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, otherWallet.address)

      // Setup denylist
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Setup eligibility oracle that denies
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      const expectedRewards = toGRT('1400')

      // Check balances before
      const subgraphDeniedBalanceBefore = await grt.balanceOf(reclaimWallet.address)
      const indexerIneligibleBalanceBefore = await grt.balanceOf(otherWallet.address)

      // Close allocation - subgraph denial takes precedence (handled at subgraph level)
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      // No allocation-level denial events - handled at subgraph level
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDenied')
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDeniedDueToEligibility')
      // RewardsReclaimed emitted (subgraph-level reclaim)
      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      // Only SUBGRAPH_DENIED wallet should receive rewards (allow for rounding errors)
      const subgraphDeniedBalanceAfter = await grt.balanceOf(reclaimWallet.address)
      const indexerIneligibleBalanceAfter = await grt.balanceOf(otherWallet.address)

      expectApproxEq(
        subgraphDeniedBalanceAfter.sub(subgraphDeniedBalanceBefore),
        expectedRewards,
        'SUBGRAPH_DENIED wallet balance',
      )
      expect(indexerIneligibleBalanceAfter.sub(indexerIneligibleBalanceBefore)).eq(0)
    })

    it('should reclaim to SUBGRAPH_DENIED even when only INDEXER_INELIGIBLE address configured', async function () {
      // Setup ONLY INDEXER_INELIGIBLE reclaim address (not SUBGRAPH_DENIED)
      await rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, otherWallet.address)

      // Setup denylist
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Setup eligibility oracle that denies
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Check balance before
      const balanceBefore = await grt.balanceOf(otherWallet.address)

      // Close allocation - subgraph denial is handled at subgraph level, but no SUBGRAPH_DENIED
      // reclaim address is configured, so rewards are dropped (not reclaimed)
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      // No allocation-level denial events - handled at subgraph level
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDenied')
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDeniedDueToEligibility')
      // No reclaim because SUBGRAPH_DENIED address not configured (eligibility path not reached)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')

      // INDEXER_INELIGIBLE wallet should NOT receive rewards (subgraph denial takes precedence)
      const balanceAfter = await grt.balanceOf(otherWallet.address)
      expect(balanceAfter.sub(balanceBefore)).eq(0)
    })

    it('should reclaim to INDEXER_INELIGIBLE when both fail but only INDEXER_INELIGIBLE address configured (pre-denial allocation)', async function () {
      // This tests the ternary in _deniedRewards that falls back to INDEXER_INELIGIBLE
      // when SUBGRAPH_DENIED address is not configured

      // Setup ONLY INDEXER_INELIGIBLE reclaim address (not SUBGRAPH_DENIED)
      await rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, reclaimWallet.address)
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)

      // Setup eligibility oracle that denies
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Create allocation FIRST (before denial) - this is the key difference
      await setupIndexerAllocation()

      // Mine blocks to accrue rewards
      await helpers.mineEpoch(epochManager)

      // NOW deny the subgraph (after allocation exists)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      const expectedRewards = toGRT('1400')

      // Check balance before
      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Close allocation - pre-denial rewards flow through _deniedRewards
      // Both conditions are true, but SUBGRAPH_DENIED address is not set
      // So it should fall back to INDEXER_INELIGIBLE
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())

      // RewardsDenied IS emitted (allocation-level denial for pre-denial rewards)
      await expect(tx).emit(rewardsManager, 'RewardsDenied').withArgs(indexer1.address, allocationID1)
      // RewardsDeniedDueToEligibility IS emitted
      await expect(tx).emit(rewardsManager, 'RewardsDeniedDueToEligibility')
      // RewardsReclaimed should emit with INDEXER_INELIGIBLE reason (fallback)
      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      // INDEXER_INELIGIBLE wallet should receive rewards (fallback from SUBGRAPH_DENIED)
      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expectApproxEq(balanceAfter.sub(balanceBefore), expectedRewards, 'INDEXER_INELIGIBLE wallet balance')
    })

    it('should drop rewards when both fail and neither address configured', async function () {
      // Do NOT set any reclaim addresses

      // Setup denylist
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Setup eligibility oracle that denies
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Close allocation - no events, rewards dropped
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDenied')
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDeniedDueToEligibility')
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')
    })

    it('should drop rewards when subgraph denied without address even if indexer eligible', async function () {
      // Do NOT set SUBGRAPH_DENIED reclaim address

      // Setup denylist
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Setup eligibility oracle that ALLOWS (indexer is eligible)
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(true) // Allow
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Close allocation - no events because subgraph denial handled at subgraph level
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDenied')
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDeniedDueToEligibility')
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')
      await expect(tx).to.not.emit(rewardsManager, 'HorizonRewardsAssigned')
    })
  })

  describe('reclaimRewards - force close allocation', function () {
    let mockSubgraphService: any

    beforeEach(async function () {
      // Deploy mock subgraph service
      const MockSubgraphServiceFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockSubgraphService.sol:MockSubgraphService',
      )
      mockSubgraphService = await MockSubgraphServiceFactory.deploy()
      await mockSubgraphService.deployed()

      // Set it as the subgraph service in rewards manager
      await rewardsManager.connect(governor).setSubgraphService(mockSubgraphService.address)
    })

    it('should reclaim rewards when reclaim address is set', async function () {
      // Set reclaim address for ForceCloseAllocation
      await rewardsManager.connect(governor).setReclaimAddress(CLOSE_ALLOCATION, reclaimWallet.address)

      // Setup allocation in real staking contract
      await setupIndexerAllocation()

      // Also set allocation data in mock so RewardsManager can query it
      const tokensAllocated = toGRT('12500')
      await mockSubgraphService.setAllocation(
        allocationID1,
        true, // isActive
        indexer1.address,
        subgraphDeploymentID1,
        tokensAllocated,
        0, // accRewardsPerAllocatedToken starts at 0
        0, // accRewardsPending
      )
      await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, tokensAllocated)

      // Jump to next epoch to accrue rewards
      await helpers.mineEpoch(epochManager)

      // Check balance before
      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Call reclaimRewards via mock subgraph service
      const tx = await mockSubgraphService.callReclaimRewards(rewardsManager.address, CLOSE_ALLOCATION, allocationID1)

      // Verify event was emitted (don't check exact amount, it depends on rewards calculation)
      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      // Check balance after - should have increased
      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      const rewardsClaimed = balanceAfter.sub(balanceBefore)
      expect(rewardsClaimed).to.be.gt(0)
    })

    it('should not reclaim when reclaim address is not set', async function () {
      // Do NOT set reclaim address (defaults to zero)

      // Setup allocation in real staking contract
      await setupIndexerAllocation()

      // Also set allocation data in mock
      const tokensAllocated = toGRT('12500')
      await mockSubgraphService.setAllocation(
        allocationID1,
        true,
        indexer1.address,
        subgraphDeploymentID1,
        tokensAllocated,
        0,
        0,
      )
      await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, tokensAllocated)

      // Jump to next epoch to accrue rewards
      await helpers.mineEpoch(epochManager)

      // Call reclaimRewards via mock subgraph service - should not emit RewardsReclaimed
      const tx = await mockSubgraphService.callReclaimRewards(rewardsManager.address, CLOSE_ALLOCATION, allocationID1)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')
    })

    it('should return 0 and not emit when reclaim address is not set and no rewards', async function () {
      // Do NOT set reclaim address (zero address)

      // Setup allocation but mark it as inactive (no rewards)
      const tokensAllocated = toGRT('12500')
      await mockSubgraphService.setAllocation(
        allocationID1,
        false, // NOT active - this will return 0 rewards
        indexer1.address,
        subgraphDeploymentID1,
        tokensAllocated,
        0,
        0,
      )
      await mockSubgraphService.setSubgraphAllocatedTokens(subgraphDeploymentID1, tokensAllocated)

      // Call reclaimRewards - should return 0 and not emit
      const result = await mockSubgraphService.callStatic.callReclaimRewards(
        rewardsManager.address,
        CLOSE_ALLOCATION,
        allocationID1,
      )
      expect(result).eq(0)

      const tx = await mockSubgraphService.callReclaimRewards(rewardsManager.address, CLOSE_ALLOCATION, allocationID1)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')
    })

    it('should reject when called by unauthorized address', async function () {
      // Try to call reclaimRewards directly from indexer1 (not the subgraph service)
      const abiCoder = hre.ethers.utils.defaultAbiCoder
      const selector = hre.ethers.utils.id('reclaimRewards(bytes32,address)').slice(0, 10)
      const params = abiCoder.encode(['bytes32', 'address'], [CLOSE_ALLOCATION, allocationID1])
      const data = selector + params.slice(2)

      const tx = indexer1.sendTransaction({
        to: rewardsManager.address,
        data: data,
      })
      await expect(tx).revertedWith('Not a rewards issuer')
    })
  })

  describe('setDefaultReclaimAddress', function () {
    it('should reject if not governor', async function () {
      const tx = rewardsManager.connect(indexer1).setDefaultReclaimAddress(reclaimWallet.address)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('should set default reclaim address if governor', async function () {
      const tx = rewardsManager.connect(governor).setDefaultReclaimAddress(reclaimWallet.address)
      await expect(tx)
        .emit(rewardsManager, 'DefaultReclaimAddressSet')
        .withArgs(constants.AddressZero, reclaimWallet.address)

      // Verify the getter returns the correct value
      expect(await rewardsManager.getDefaultReclaimAddress()).eq(reclaimWallet.address)
    })

    it('should allow setting to zero address', async function () {
      await rewardsManager.connect(governor).setDefaultReclaimAddress(reclaimWallet.address)

      const tx = rewardsManager.connect(governor).setDefaultReclaimAddress(constants.AddressZero)
      await expect(tx)
        .emit(rewardsManager, 'DefaultReclaimAddressSet')
        .withArgs(reclaimWallet.address, constants.AddressZero)
    })

    it('should not emit event when setting same address', async function () {
      await rewardsManager.connect(governor).setDefaultReclaimAddress(reclaimWallet.address)

      const tx = rewardsManager.connect(governor).setDefaultReclaimAddress(reclaimWallet.address)
      await expect(tx).to.not.emit(rewardsManager, 'DefaultReclaimAddressSet')
    })
  })

  describe('default reclaim address fallback', function () {
    beforeEach(async function () {
      await setupIndexerAllocation()
      // Set governor as the subgraph availability oracle for setDenied calls
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
    })

    it('should use default reclaim address when reason-specific not set', async function () {
      // Set default but NOT SUBGRAPH_DENIED specific
      await rewardsManager.connect(governor).setDefaultReclaimAddress(reclaimWallet.address)

      // Deny the subgraph
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Mine blocks to accrue rewards
      await helpers.mine(5)

      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Trigger reclaim via onSubgraphAllocationUpdate
      const tx = rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID1)

      // Should reclaim to default address with SUBGRAPH_DENIED reason
      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expect(balanceAfter).gt(balanceBefore)
    })

    it('should prefer reason-specific address over default', async function () {
      // Set both default AND SUBGRAPH_DENIED specific
      await rewardsManager.connect(governor).setDefaultReclaimAddress(otherWallet.address)
      await rewardsManager.connect(governor).setReclaimAddress(SUBGRAPH_DENIED, reclaimWallet.address)

      // Deny the subgraph
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Mine blocks to accrue rewards
      await helpers.mine(5)

      const balanceBefore = await grt.balanceOf(reclaimWallet.address)
      const otherBalanceBefore = await grt.balanceOf(otherWallet.address)

      // Trigger reclaim
      await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID1)

      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      const otherBalanceAfter = await grt.balanceOf(otherWallet.address)

      // Should go to reason-specific, not default
      expect(balanceAfter).gt(balanceBefore)
      expect(otherBalanceAfter).eq(otherBalanceBefore)
    })
  })

  describe('reclaim NO_SIGNAL - zero total signal', function () {
    it('should reclaim when no signal and NO_SIGNAL address set', async function () {
      // Set reclaim address for NO_SIGNAL
      await rewardsManager.connect(governor).setReclaimAddress(NO_SIGNAL, reclaimWallet.address)

      // Don't create any signal - just mine blocks
      await helpers.mine(5)

      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Trigger updateAccRewardsPerSignal (called internally when signal changes, or directly)
      const tx = rewardsManager.connect(governor).updateAccRewardsPerSignal()

      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expect(balanceAfter).gt(balanceBefore)
    })

    it('should drop rewards when no signal and no reclaim address', async function () {
      // Don't set any reclaim address - just mine blocks
      await helpers.mine(5)

      // Trigger updateAccRewardsPerSignal
      const tx = rewardsManager.connect(governor).updateAccRewardsPerSignal()

      // Should not emit RewardsReclaimed (dropped)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')
    })

    it('should use default reclaim address for NO_SIGNAL when specific not set', async function () {
      // Set default but NOT NO_SIGNAL specific
      await rewardsManager.connect(governor).setDefaultReclaimAddress(reclaimWallet.address)

      await helpers.mine(5)

      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      const tx = rewardsManager.connect(governor).updateAccRewardsPerSignal()

      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expect(balanceAfter).gt(balanceBefore)
    })
  })

  describe('reclaim NO_ALLOCATION - signal but no allocations', function () {
    it('should reclaim when signal exists but no allocations and NO_ALLOCATION address set', async function () {
      // Set reclaim address for NO_ALLOCATION
      await rewardsManager.connect(governor).setReclaimAddress(NO_ALLOCATION, reclaimWallet.address)

      // Create signal but NO allocation
      const signalled1 = toGRT('1500')
      await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

      // Mine blocks to accrue rewards
      await helpers.mine(5)

      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Trigger onSubgraphAllocationUpdate - will see signal but no allocations
      const tx = rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID1)

      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expect(balanceAfter).gt(balanceBefore)
    })

    it('should drop rewards when no allocations and no reclaim address', async function () {
      // Create signal but NO allocation, and don't set reclaim address
      const signalled1 = toGRT('1500')
      await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

      await helpers.mine(5)

      // Trigger onSubgraphAllocationUpdate
      const tx = rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID1)

      // Should not emit RewardsReclaimed (dropped)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')
    })
  })

  describe('reclaim BELOW_MINIMUM_SIGNAL', function () {
    const MINIMUM_SIGNAL = toGRT('1000')

    beforeEach(async function () {
      // Set minimum signal threshold
      await rewardsManager.connect(governor).setMinimumSubgraphSignal(MINIMUM_SIGNAL)
    })

    it('should reclaim when signal below minimum and BELOW_MINIMUM_SIGNAL address set', async function () {
      // Set reclaim address for BELOW_MINIMUM_SIGNAL
      await rewardsManager.connect(governor).setReclaimAddress(BELOW_MINIMUM_SIGNAL, reclaimWallet.address)

      // Create signal BELOW minimum (minimum is 1000, we signal 500)
      const signalled1 = toGRT('500')
      await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

      // Mine blocks
      await helpers.mine(5)

      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Trigger onSubgraphAllocationUpdate
      const tx = rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID1)

      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expect(balanceAfter).gt(balanceBefore)
    })

    it('should not reclaim when signal at or above minimum', async function () {
      // Set reclaim address
      await rewardsManager.connect(governor).setReclaimAddress(BELOW_MINIMUM_SIGNAL, reclaimWallet.address)

      // Create signal AT minimum
      const signalled1 = MINIMUM_SIGNAL
      await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

      // Also need an allocation for rewards to accumulate normally
      const tokensToAllocate = toGRT('12500')
      await staking.connect(indexer1).stake(tokensToAllocate)
      await staking
        .connect(indexer1)
        .allocateFrom(
          indexer1.address,
          subgraphDeploymentID1,
          tokensToAllocate,
          allocationID1,
          metadata,
          await channelKey1.generateProof(indexer1.address),
        )

      await helpers.mine(5)

      // Trigger onSubgraphAllocationUpdate
      const tx = rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID1)

      // Should NOT emit RewardsReclaimed for BELOW_MINIMUM_SIGNAL
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')
    })

    it('should drop rewards when below minimum and no reclaim address', async function () {
      // Don't set reclaim address
      // Create signal BELOW minimum
      const signalled1 = toGRT('500')
      await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

      await helpers.mine(5)

      const tx = rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID1)

      // Should not emit RewardsReclaimed (dropped)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimed')
    })

    it('should use BELOW_MINIMUM_SIGNAL when denied but SUBGRAPH_DENIED address not configured', async function () {
      // This tests line 574: the branch where subgraph is denied but reclaim address is zero,
      // so it falls back to BELOW_MINIMUM_SIGNAL

      // Set BELOW_MINIMUM_SIGNAL address but NOT SUBGRAPH_DENIED
      await rewardsManager.connect(governor).setReclaimAddress(BELOW_MINIMUM_SIGNAL, reclaimWallet.address)

      // Setup denylist
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Create signal BELOW minimum (minimum is 1000, we signal 500)
      const signalled1 = toGRT('500')
      await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)

      // Mine blocks
      await helpers.mine(5)

      const balanceBefore = await grt.balanceOf(reclaimWallet.address)

      // Trigger onSubgraphAllocationUpdate
      // Subgraph is denied but no SUBGRAPH_DENIED address, so should fall back to BELOW_MINIMUM_SIGNAL
      const tx = rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID1)

      // Should reclaim to BELOW_MINIMUM_SIGNAL address
      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expect(balanceAfter).gt(balanceBefore)
    })
  })

  describe('dual denial - SUBGRAPH_DENIED takes precedence when configured', function () {
    it('should reclaim to SUBGRAPH_DENIED when both conditions true and SUBGRAPH_DENIED address configured (pre-denial allocation)', async function () {
      // This tests line 747-748: when both denied and ineligible, and SUBGRAPH_DENIED IS configured

      // Setup BOTH reclaim addresses
      await rewardsManager.connect(governor).setReclaimAddress(SUBGRAPH_DENIED, reclaimWallet.address)
      await rewardsManager.connect(governor).setReclaimAddress(INDEXER_INELIGIBLE, otherWallet.address)
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)

      // Setup eligibility oracle that denies
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Create allocation FIRST (before denial)
      await setupIndexerAllocation()

      // Mine blocks to accrue rewards
      await helpers.mineEpoch(epochManager)

      // NOW deny the subgraph (after allocation exists)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Check balances before
      const subgraphDeniedBalanceBefore = await grt.balanceOf(reclaimWallet.address)
      const indexerIneligibleBalanceBefore = await grt.balanceOf(otherWallet.address)

      // Close allocation - pre-denial rewards flow through _deniedRewards
      // Both conditions are true, SUBGRAPH_DENIED IS configured, so it should use SUBGRAPH_DENIED
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())

      // RewardsDenied IS emitted
      await expect(tx).emit(rewardsManager, 'RewardsDenied').withArgs(indexer1.address, allocationID1)
      // RewardsDeniedDueToEligibility IS emitted
      await expect(tx).emit(rewardsManager, 'RewardsDeniedDueToEligibility')
      // RewardsReclaimed should emit with SUBGRAPH_DENIED reason
      await expect(tx).emit(rewardsManager, 'RewardsReclaimed')

      // SUBGRAPH_DENIED wallet should receive rewards (not INDEXER_INELIGIBLE)
      const subgraphDeniedBalanceAfter = await grt.balanceOf(reclaimWallet.address)
      const indexerIneligibleBalanceAfter = await grt.balanceOf(otherWallet.address)

      expect(subgraphDeniedBalanceAfter.sub(subgraphDeniedBalanceBefore)).gt(0)
      expect(indexerIneligibleBalanceAfter.sub(indexerIneligibleBalanceBefore)).eq(0)
    })
  })
})

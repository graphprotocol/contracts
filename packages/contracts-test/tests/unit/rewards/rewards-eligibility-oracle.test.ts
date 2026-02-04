import { Curation } from '@graphprotocol/contracts'
import { EpochManager } from '@graphprotocol/contracts'
import { GraphToken } from '@graphprotocol/contracts'
import { IStaking } from '@graphprotocol/contracts'
import { RewardsManager } from '@graphprotocol/contracts'
import { deriveChannelKey, GraphNetworkContracts, helpers, randomHexBytes, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { BigNumber, constants } from 'ethers'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

const { HashZero } = constants

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

describe('Rewards - Eligibility Oracle', () => {
  const graph = hre.graph()
  let curator1: SignerWithAddress
  let governor: SignerWithAddress
  let indexer1: SignerWithAddress

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

  describe('rewards eligibility oracle', function () {
    it('should reject setRewardsEligibilityOracle if unauthorized', async function () {
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(true)
      await mockOracle.deployed()
      const tx = rewardsManager.connect(indexer1).setRewardsEligibilityOracle(mockOracle.address)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('should set rewards eligibility oracle if governor', async function () {
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(true)
      await mockOracle.deployed()

      const tx = rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)
      await expect(tx)
        .emit(rewardsManager, 'RewardsEligibilityOracleSet')
        .withArgs(constants.AddressZero, mockOracle.address)

      expect(await rewardsManager.getRewardsEligibilityOracle()).eq(mockOracle.address)
    })

    it('should allow setting rewards eligibility oracle to zero address', async function () {
      // First set an oracle
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(true)
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Then set to zero address to disable
      const tx = rewardsManager.connect(governor).setRewardsEligibilityOracle(constants.AddressZero)
      await expect(tx)
        .emit(rewardsManager, 'RewardsEligibilityOracleSet')
        .withArgs(mockOracle.address, constants.AddressZero)

      expect(await rewardsManager.getRewardsEligibilityOracle()).eq(constants.AddressZero)
    })

    it('should reject setting oracle that does not support interface', async function () {
      // Try to set an EOA (externally owned account) as the rewards eligibility oracle
      const tx = rewardsManager.connect(governor).setRewardsEligibilityOracle(indexer1.address)
      // EOA doesn't have code, so the call will revert (error message may vary by ethers version)
      await expect(tx).to.be.reverted
    })

    it('should reject setting oracle that does not support IRewardsEligibility interface', async function () {
      // Deploy a contract that supports ERC165 but not IRewardsEligibility
      const MockERC165Factory = await hre.ethers.getContractFactory('contracts/tests/MockERC165.sol:MockERC165')
      const mockERC165 = await MockERC165Factory.deploy()
      await mockERC165.deployed()

      const tx = rewardsManager.connect(governor).setRewardsEligibilityOracle(mockERC165.address)
      await expect(tx).revertedWith('Contract does not support IRewardsEligibility interface')
    })

    it('should not emit event when setting same oracle address', async function () {
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(true)
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Setting the same oracle again should not emit an event
      const tx = rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsEligibilityOracleSet')
    })
  })

  describe('rewards eligibility in takeRewards', function () {
    it('should deny rewards due to rewards eligibility oracle', async function () {
      // Setup rewards eligibility oracle that denies rewards for indexer1
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Default to deny
      await mockOracle.deployed()

      // Set the rewards eligibility oracle
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Calculate expected rewards (for verification in the event)
      const expectedIndexingRewards = toGRT('1400')

      // Close allocation. At this point rewards should be denied due to eligibility
      const tx = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt = await tx.wait()

      // Parse RewardsManager events from the transaction receipt
      const rewardsDeniedEvents = receipt.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .filter((event) => event?.name === 'RewardsDeniedDueToEligibility')

      expect(rewardsDeniedEvents.length).to.equal(1, 'RewardsDeniedDueToEligibility event not found')
      const event = rewardsDeniedEvents[0]!
      expect(event.args[0]).to.equal(indexer1.address)
      expect(event.args[1]).to.equal(allocationID1)
      expectApproxEq(event.args[2], expectedIndexingRewards, 'rewards amount')
    })

    it('should allow rewards when rewards eligibility oracle approves', async function () {
      // Setup rewards eligibility oracle that allows rewards for indexer1
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(true) // Default to allow
      await mockOracle.deployed()

      // Set the rewards eligibility oracle
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Calculate expected rewards
      const expectedIndexingRewards = toGRT('1400')

      // Close allocation. At this point rewards should be assigned normally
      const tx = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt = await tx.wait()

      // Parse RewardsManager events from the transaction receipt
      const rewardsAssignedEvents = receipt.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .filter((event) => event?.name === 'HorizonRewardsAssigned')

      expect(rewardsAssignedEvents.length).to.equal(1, 'HorizonRewardsAssigned event not found')
      const event = rewardsAssignedEvents[0]!
      expect(event.args[0]).to.equal(indexer1.address)
      expect(event.args[1]).to.equal(allocationID1)
      expectApproxEq(event.args[2], expectedIndexingRewards, 'rewards amount')
    })
  })

  describe('rewards eligibility oracle and denylist interaction', function () {
    // Note: With subgraph-level denial, rewards for denied subgraphs are handled via
    // onSubgraphAllocationUpdate() at the subgraph level. The allocation-level _deniedRewards()
    // path (which checks eligibility) is not reached because rewards = 0 for allocations
    // created while denied (frozen accumulator).

    it('should prioritize denylist over REO when both deny', async function () {
      // Setup BOTH denial mechanisms
      // 1. Setup denylist
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // 2. Setup REO that also denies
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation (created while denied - accumulator frozen)
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Close allocation - subgraph denial takes precedence (handled at subgraph level)
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())

      // With subgraph-level denial, rewards = 0 (frozen accumulator), so allocation-level
      // denial events are not emitted. Rewards are reclaimed at subgraph level.
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDenied')
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDeniedDueToEligibility')
      await expect(tx).to.not.emit(rewardsManager, 'HorizonRewardsAssigned')
    })

    it('should check REO when denylist allows but indexer ineligible', async function () {
      // Setup: Subgraph is allowed (no denylist), but indexer is ineligible
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Deny indexer
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      const expectedIndexingRewards = toGRT('1400')

      // Close allocation - REO should be checked
      const tx = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt = await tx.wait()

      // Parse RewardsManager events from the transaction receipt
      const rewardsDeniedEvents = receipt.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .filter((event) => event?.name === 'RewardsDeniedDueToEligibility')

      expect(rewardsDeniedEvents.length).to.equal(1, 'RewardsDeniedDueToEligibility event not found')
      const event = rewardsDeniedEvents[0]!
      expect(event.args[0]).to.equal(indexer1.address)
      expect(event.args[1]).to.equal(allocationID1)
      expectApproxEq(event.args[2], expectedIndexingRewards, 'rewards amount')
    })

    it('should handle indexer becoming ineligible mid-allocation', async function () {
      // Setup: Indexer starts eligible
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(true) // Start eligible
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation while indexer is eligible
      await setupIndexerAllocation()

      // Jump to next epoch (rewards accrue)
      await helpers.mineEpoch(epochManager)

      // Change eligibility AFTER allocation created but BEFORE closing
      await mockOracle.setIndexerEligible(indexer1.address, false)

      const expectedIndexingRewards = toGRT('1600')

      // Close allocation - should be denied at close time (not creation time)
      const tx = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt = await tx.wait()

      // Parse RewardsManager events from the transaction receipt
      const rewardsDeniedEvents = receipt.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .filter((event) => event?.name === 'RewardsDeniedDueToEligibility')

      expect(rewardsDeniedEvents.length).to.equal(1, 'RewardsDeniedDueToEligibility event not found')
      const event = rewardsDeniedEvents[0]!
      expect(event.args[0]).to.equal(indexer1.address)
      expect(event.args[1]).to.equal(allocationID1)
      expectApproxEq(event.args[2], expectedIndexingRewards, 'rewards amount')
    })

    it('should handle indexer becoming eligible mid-allocation', async function () {
      // Setup: Indexer starts ineligible
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false) // Start ineligible
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation while indexer is ineligible
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      // Change eligibility before closing
      await mockOracle.setIndexerEligible(indexer1.address, true)

      const expectedIndexingRewards = toGRT('1600')

      // Close allocation - should now be allowed
      const tx = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt = await tx.wait()

      // Parse RewardsManager events from the transaction receipt
      const rewardsAssignedEvents = receipt.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .filter((event) => event?.name === 'HorizonRewardsAssigned')

      expect(rewardsAssignedEvents.length).to.equal(1, 'HorizonRewardsAssigned event not found')
      const event = rewardsAssignedEvents[0]!
      expect(event.args[0]).to.equal(indexer1.address)
      expect(event.args[1]).to.equal(allocationID1)
      expectApproxEq(event.args[2], expectedIndexingRewards, 'rewards amount')
    })

    it('should handle denylist being added mid-allocation', async function () {
      // Setup: Start with subgraph NOT denied
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation when subgraph is allowed
      await setupIndexerAllocation()

      // Jump to next epoch (rewards accrue)
      await helpers.mineEpoch(epochManager)

      // Deny the subgraph before closing allocation
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Close allocation - should be denied even though it was created when allowed
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      await expect(tx).emit(rewardsManager, 'RewardsDenied').withArgs(indexer1.address, allocationID1)
    })

    it('should handle denylist being removed mid-allocation', async function () {
      // Setup: Start with subgraph denied
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation (created while denied - accumulator frozen at this point)
      await setupIndexerAllocation()

      // Jump to next epoch (rewards accrue but are reclaimed at subgraph level while denied)
      await helpers.mineEpoch(epochManager)

      // Remove from denylist - this snapshots and starts accumulator updating again
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, false)

      // Wait for another epoch to accrue POST-undeny rewards
      // Only post-undeny rewards are available (denied-period rewards were reclaimed)
      await helpers.mineEpoch(epochManager)

      // Close allocation - should get post-undeny rewards only
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      // Verify rewards are assigned (exact amount depends on blocks since undeny)
      await expect(tx).emit(rewardsManager, 'HorizonRewardsAssigned')
    })

    it('should allow rewards when REO is zero address (disabled)', async function () {
      // Ensure REO is not set (zero address = disabled)
      expect(await rewardsManager.getRewardsEligibilityOracle()).eq(constants.AddressZero)

      // Align with the epoch boundary
      await helpers.mineEpoch(epochManager)

      // Setup allocation
      await setupIndexerAllocation()

      // Jump to next epoch
      await helpers.mineEpoch(epochManager)

      const expectedIndexingRewards = toGRT('1400')

      // Close allocation - should get rewards (no eligibility check when REO is zero)
      const tx = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt = await tx.wait()

      // Parse RewardsManager events from the transaction receipt
      const rewardsAssignedEvents = receipt.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .filter((event) => event?.name === 'HorizonRewardsAssigned')

      expect(rewardsAssignedEvents.length).to.equal(1, 'HorizonRewardsAssigned event not found')
      const event = rewardsAssignedEvents[0]!
      expect(event.args[0]).to.equal(indexer1.address)
      expect(event.args[1]).to.equal(allocationID1)
      expectApproxEq(event.args[2], expectedIndexingRewards, 'rewards amount')
    })

    it('should verify event structure differences between denial mechanisms', async function () {
      // Test 1: Denylist denial - event WITHOUT amount
      // Create allocation FIRST, then deny (so there are pre-denial rewards to deny)
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)

      await helpers.mineEpoch(epochManager)
      await setupIndexerAllocation()
      await helpers.mineEpoch(epochManager)

      // Deny AFTER allocation created (so rewards have accrued)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

      const tx1 = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt1 = await tx1.wait()

      // Find the RewardsDenied event - search in logs as events may be from different contracts
      const rewardsDeniedEvent = receipt1.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .find((event) => event?.name === 'RewardsDenied')

      expect(rewardsDeniedEvent).to.not.be.undefined

      // Verify it only has indexer and allocationID (no amount parameter)
      expect(rewardsDeniedEvent?.args?.indexer).to.equal(indexer1.address)
      expect(rewardsDeniedEvent?.args?.allocationID).to.equal(allocationID1)
      // RewardsDenied has only 2 args, amount should not exist
      expect(rewardsDeniedEvent?.args?.amount).to.be.undefined

      // Reset for test 2
      await fixture.tearDown()
      await fixture.setUp()

      // Test 2: REO denial - event WITH amount
      const MockRewardsEligibilityOracleFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockRewardsEligibilityOracle.sol:MockRewardsEligibilityOracle',
      )
      const mockOracle = await MockRewardsEligibilityOracleFactory.deploy(false)
      await mockOracle.deployed()
      await rewardsManager.connect(governor).setRewardsEligibilityOracle(mockOracle.address)

      await helpers.mineEpoch(epochManager)
      await setupIndexerAllocation()
      await helpers.mineEpoch(epochManager)

      const tx2 = await staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      const receipt2 = await tx2.wait()

      // Find the RewardsDeniedDueToEligibility event
      const eligibilityEvent = receipt2.logs
        .map((log) => {
          try {
            return rewardsManager.interface.parseLog(log)
          } catch {
            return null
          }
        })
        .find((event) => event?.name === 'RewardsDeniedDueToEligibility')

      expect(eligibilityEvent).to.not.be.undefined

      // Verify it has indexer, allocationID, AND amount
      expect(eligibilityEvent?.args?.indexer).to.equal(indexer1.address)
      expect(eligibilityEvent?.args?.allocationID).to.equal(allocationID1)
      expect(eligibilityEvent?.args?.amount).to.not.be.undefined
      expect(eligibilityEvent?.args?.amount).to.be.gt(0) // Shows what they would have gotten
    })
  })
})

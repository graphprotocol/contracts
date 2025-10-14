import { Curation } from '@graphprotocol/contracts'
import { EpochManager } from '@graphprotocol/contracts'
import { GraphToken } from '@graphprotocol/contracts'
import { IStaking } from '@graphprotocol/contracts'
import { RewardsManager } from '@graphprotocol/contracts'
import { deriveChannelKey, GraphNetworkContracts, helpers, randomHexBytes, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { constants } from 'ethers'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

const { HashZero } = constants

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

      expect(await rewardsManager.rewardsEligibilityOracle()).eq(mockOracle.address)
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

      expect(await rewardsManager.rewardsEligibilityOracle()).eq(constants.AddressZero)
    })

    it('should reject setting oracle that does not support interface', async function () {
      // Try to set an EOA (externally owned account) as the rewards eligibility oracle
      const tx = rewardsManager.connect(governor).setRewardsEligibilityOracle(indexer1.address)
      // EOA doesn't have code, so the call will revert (error message may vary by ethers version)
      await expect(tx).to.be.reverted
    })

    it('should reject setting oracle that does not support IRewardsEligibility interface', async function () {
      // Deploy a contract that doesn't support the IRewardsEligibility interface
      const MockERC165OnlyContractFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockERC165OnlyContract.sol:MockERC165OnlyContract',
      )
      const mockContract = await MockERC165OnlyContractFactory.deploy()
      await mockContract.deployed()

      const tx = rewardsManager.connect(governor).setRewardsEligibilityOracle(mockContract.address)
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
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      await expect(tx)
        .emit(rewardsManager, 'RewardsDeniedDueToEligibility')
        .withArgs(indexer1.address, allocationID1, expectedIndexingRewards)
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
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      await expect(tx)
        .emit(rewardsManager, 'HorizonRewardsAssigned')
        .withArgs(indexer1.address, allocationID1, expectedIndexingRewards)
    })
  })
})

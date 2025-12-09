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

describe('Rewards - Reclaim Addresses', () => {
  const graph = hre.graph()
  let curator1: SignerWithAddress
  let governor: SignerWithAddress
  let indexer1: SignerWithAddress
  let reclaimWallet: SignerWithAddress

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

  describe('setIndexerEligibilityReclaimAddress', function () {
    it('should reject if not governor', async function () {
      const tx = rewardsManager.connect(indexer1).setIndexerEligibilityReclaimAddress(reclaimWallet.address)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('should set eligibility reclaim address if governor', async function () {
      const tx = rewardsManager.connect(governor).setIndexerEligibilityReclaimAddress(reclaimWallet.address)
      await expect(tx)
        .emit(rewardsManager, 'EligibilityReclaimAddressSet')
        .withArgs(constants.AddressZero, reclaimWallet.address)

      expect(await rewardsManager.indexerEligibilityReclaimAddress()).eq(reclaimWallet.address)
    })

    it('should allow setting to zero address', async function () {
      await rewardsManager.connect(governor).setIndexerEligibilityReclaimAddress(reclaimWallet.address)

      const tx = rewardsManager.connect(governor).setIndexerEligibilityReclaimAddress(constants.AddressZero)
      await expect(tx)
        .emit(rewardsManager, 'EligibilityReclaimAddressSet')
        .withArgs(reclaimWallet.address, constants.AddressZero)

      expect(await rewardsManager.indexerEligibilityReclaimAddress()).eq(constants.AddressZero)
    })

    it('should not emit event when setting same address', async function () {
      await rewardsManager.connect(governor).setIndexerEligibilityReclaimAddress(reclaimWallet.address)

      const tx = rewardsManager.connect(governor).setIndexerEligibilityReclaimAddress(reclaimWallet.address)
      await expect(tx).to.not.emit(rewardsManager, 'EligibilityReclaimAddressSet')
    })
  })

  describe('setSubgraphDeniedReclaimAddress', function () {
    it('should reject if not governor', async function () {
      const tx = rewardsManager.connect(indexer1).setSubgraphDeniedReclaimAddress(reclaimWallet.address)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('should set subgraph reclaim address if governor', async function () {
      const tx = rewardsManager.connect(governor).setSubgraphDeniedReclaimAddress(reclaimWallet.address)
      await expect(tx)
        .emit(rewardsManager, 'SubgraphReclaimAddressSet')
        .withArgs(constants.AddressZero, reclaimWallet.address)

      expect(await rewardsManager.subgraphDeniedReclaimAddress()).eq(reclaimWallet.address)
    })

    it('should allow setting to zero address', async function () {
      await rewardsManager.connect(governor).setSubgraphDeniedReclaimAddress(reclaimWallet.address)

      const tx = rewardsManager.connect(governor).setSubgraphDeniedReclaimAddress(constants.AddressZero)
      await expect(tx)
        .emit(rewardsManager, 'SubgraphReclaimAddressSet')
        .withArgs(reclaimWallet.address, constants.AddressZero)

      expect(await rewardsManager.subgraphDeniedReclaimAddress()).eq(constants.AddressZero)
    })

    it('should not emit event when setting same address', async function () {
      await rewardsManager.connect(governor).setSubgraphDeniedReclaimAddress(reclaimWallet.address)

      const tx = rewardsManager.connect(governor).setSubgraphDeniedReclaimAddress(reclaimWallet.address)
      await expect(tx).to.not.emit(rewardsManager, 'SubgraphReclaimAddressSet')
    })
  })

  describe('reclaim denied rewards - subgraph denylist', function () {
    it('should mint to reclaim address when subgraph denied and reclaim address set', async function () {
      // Setup reclaim address
      await rewardsManager.connect(governor).setSubgraphDeniedReclaimAddress(reclaimWallet.address)

      // Setup denylist
      await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)

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
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      await expect(tx).emit(rewardsManager, 'RewardsDenied').withArgs(indexer1.address, allocationID1)
      await expect(tx)
        .emit(rewardsManager, 'RewardsReclaimedDueToSubgraphDenylist')
        .withArgs(indexer1.address, allocationID1, subgraphDeploymentID1, expectedRewards)

      // Check reclaim wallet received the rewards
      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expect(balanceAfter.sub(balanceBefore)).eq(expectedRewards)
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

      // Close allocation - should only emit denial event, not reclaim
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      await expect(tx).emit(rewardsManager, 'RewardsDenied').withArgs(indexer1.address, allocationID1)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimedDueToSubgraphDenylist')
    })
  })

  describe('reclaim denied rewards - eligibility', function () {
    it('should mint to reclaim address when eligibility denied and reclaim address set', async function () {
      // Setup reclaim address
      await rewardsManager.connect(governor).setIndexerEligibilityReclaimAddress(reclaimWallet.address)

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
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      await expect(tx)
        .emit(rewardsManager, 'RewardsDeniedDueToEligibility')
        .withArgs(indexer1.address, allocationID1, expectedRewards)
      await expect(tx)
        .emit(rewardsManager, 'RewardsReclaimedDueToEligibility')
        .withArgs(indexer1.address, allocationID1, expectedRewards)

      // Check reclaim wallet received the rewards
      const balanceAfter = await grt.balanceOf(reclaimWallet.address)
      expect(balanceAfter.sub(balanceBefore)).eq(expectedRewards)
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
      const tx = staking.connect(indexer1).closeAllocation(allocationID1, randomHexBytes())
      await expect(tx)
        .emit(rewardsManager, 'RewardsDeniedDueToEligibility')
        .withArgs(indexer1.address, allocationID1, expectedRewards)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsReclaimedDueToEligibility')
    })
  })
})

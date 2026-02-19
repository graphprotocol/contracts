import { Curation } from '@graphprotocol/contracts'
import { GraphToken } from '@graphprotocol/contracts'
import { IStaking } from '@graphprotocol/contracts'
import { RewardsManager } from '@graphprotocol/contracts'
import { GraphNetworkContracts, helpers, randomHexBytes, toBN, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { BigNumber } from 'ethers'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

const ISSUANCE_PER_BLOCK = toBN('200000000000000000000') // 200 GRT every block

describe('Rewards - Configuration', () => {
  const graph = hre.graph()
  let governor: SignerWithAddress
  let indexer1: SignerWithAddress
  let indexer2: SignerWithAddress
  let curator1: SignerWithAddress
  let curator2: SignerWithAddress
  let oracle: SignerWithAddress
  let assetHolder: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let grt: GraphToken
  let curation: Curation
  let staking: IStaking
  let rewardsManager: RewardsManager

  const subgraphDeploymentID1 = randomHexBytes()

  before(async function () {
    const testAccounts = await graph.getTestAccounts()
    ;[indexer1, indexer2, curator1, curator2, oracle, assetHolder] = testAccounts
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    grt = contracts.GraphToken as GraphToken
    curation = contracts.Curation as Curation
    staking = contracts.Staking as IStaking
    rewardsManager = contracts.RewardsManager

    // 200 GRT per block
    await rewardsManager.connect(governor).setIssuancePerBlock(ISSUANCE_PER_BLOCK)

    // Distribute test funds
    for (const wallet of [indexer1, indexer2, curator1, curator2, assetHolder]) {
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

  describe('configuration', function () {
    describe('initialize', function () {
      it('should revert when called on implementation contract', async function () {
        // Try to call initialize on the implementation contract (should revert with onlyImpl)
        const tx = rewardsManager.connect(governor).initialize(contracts.Controller.address)
        await expect(tx).revertedWith('Only implementation')
      })
    })

    describe('issuance per block update', function () {
      it('should reject set issuance per block if unauthorized', async function () {
        const tx = rewardsManager.connect(indexer1).setIssuancePerBlock(toGRT('1.025'))
        await expect(tx).revertedWith('Only Controller governor')
      })

      it('should set issuance rate to minimum allowed (0)', async function () {
        const newIssuancePerBlock = toGRT('0')
        await rewardsManager.connect(governor).setIssuancePerBlock(newIssuancePerBlock)
        expect(await rewardsManager.issuancePerBlock()).eq(newIssuancePerBlock)
      })

      it('should set issuance rate', async function () {
        const newIssuancePerBlock = toGRT('100.025')
        await rewardsManager.connect(governor).setIssuancePerBlock(newIssuancePerBlock)
        expect(await rewardsManager.issuancePerBlock()).eq(newIssuancePerBlock)
        expect(await rewardsManager.accRewardsPerSignalLastBlockUpdated()).eq(await helpers.latestBlock())
      })

      it('should update timestamp when transitioning from zero to non-zero issuance', async function () {
        // Add some signal so rewards can be calculated
        await curation.connect(curator1).mint(subgraphDeploymentID1, toGRT('10000'), 0)

        // Mine some blocks with rewards active
        await helpers.mine(10)

        // Set issuance to zero - this updates timestamp correctly
        await rewardsManager.connect(governor).setIssuancePerBlock(0)
        const blockAfterZeroIssuance = await helpers.latestBlock()

        // Verify timestamp was updated
        const timestampAfterZero = await rewardsManager.accRewardsPerSignalLastBlockUpdated()
        expect(timestampAfterZero).to.equal(blockAfterZeroIssuance)

        // Mine blocks during zero issuance period
        await helpers.mine(10)

        // Set issuance back to non-zero
        await rewardsManager.connect(governor).setIssuancePerBlock(ISSUANCE_PER_BLOCK)
        const blockAfterRestore = await helpers.latestBlock()

        // Timestamp should be updated when transitioning from zero issuance
        const timestampAfterRestore = await rewardsManager.accRewardsPerSignalLastBlockUpdated()
        expect(timestampAfterRestore).to.equal(
          blockAfterRestore,
          'Timestamp should be updated when transitioning from zero issuance',
        )
      })

      it('should not over-issue rewards after zero issuance period', async function () {
        // Add signal
        await curation.connect(curator1).mint(subgraphDeploymentID1, toGRT('10000'), 0)

        // Get signalled tokens for calculation
        const signalledTokens = await grt.balanceOf(curation.address)

        // Mine some blocks with rewards active
        await helpers.mine(10)

        // Capture rewards and timestamp before zero issuance period
        await rewardsManager.connect(governor).updateAccRewardsPerSignal()
        const rewardsAfterFirstPeriod = await rewardsManager.accRewardsPerSignal()

        // Set issuance to zero
        await rewardsManager.connect(governor).setIssuancePerBlock(0)
        const timestampAfterZeroSet = await rewardsManager.accRewardsPerSignalLastBlockUpdated()

        // Mine blocks during zero issuance - NO rewards should accumulate
        await helpers.mine(10)

        // Restore issuance - record the block when non-zero issuance starts
        await rewardsManager.connect(governor).setIssuancePerBlock(ISSUANCE_PER_BLOCK)
        const timestampAfterRestore = await rewardsManager.accRewardsPerSignalLastBlockUpdated()

        // Mine more blocks with rewards active
        await helpers.mine(10)

        // Update and check final rewards
        await rewardsManager.connect(governor).updateAccRewardsPerSignal()
        const finalRewards = await rewardsManager.accRewardsPerSignal()
        const finalTimestamp = await rewardsManager.accRewardsPerSignalLastBlockUpdated()

        // The actual rewards increase from first period to final
        const rewardsIncrease = finalRewards.sub(rewardsAfterFirstPeriod)

        // Calculate expected rewards based on ACTUAL blocks where issuance was active
        const FIXED_POINT_SCALING_FACTOR = BigNumber.from(10).pow(18)
        const activeBlocksAfterRestore = finalTimestamp.sub(timestampAfterRestore)
        const expectedIncrease = ISSUANCE_PER_BLOCK.mul(activeBlocksAfterRestore)
          .mul(FIXED_POINT_SCALING_FACTOR)
          .div(signalledTokens)

        // Key assertion: timestamp should advance during zero issuance period
        expect(timestampAfterRestore.toNumber()).to.be.greaterThan(
          timestampAfterZeroSet.toNumber(),
          'Timestamp should advance when setting non-zero issuance',
        )

        // Allow some tolerance for block timing (1 block variance)
        const tolerance = ISSUANCE_PER_BLOCK.mul(1).mul(FIXED_POINT_SCALING_FACTOR).div(signalledTokens)

        // Rewards should match the active period only
        expect(rewardsIncrease).to.be.closeTo(expectedIncrease, tolerance, 'Rewards should match active period only')
      })
    })

    describe('subgraph availability service', function () {
      it('should reject set subgraph oracle if unauthorized', async function () {
        const tx = rewardsManager.connect(indexer1).setSubgraphAvailabilityOracle(oracle.address)
        await expect(tx).revertedWith('Only Controller governor')
      })

      it('should set subgraph oracle if governor', async function () {
        await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(oracle.address)
        expect(await rewardsManager.subgraphAvailabilityOracle()).eq(oracle.address)
      })

      it('should reject to deny subgraph if not the oracle', async function () {
        const tx = rewardsManager.connect(governor).setDenied(subgraphDeploymentID1, true)
        await expect(tx).revertedWith('Caller must be the subgraph availability oracle')
      })

      it('should deny subgraph', async function () {
        await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(oracle.address)

        const tx = rewardsManager.connect(oracle).setDenied(subgraphDeploymentID1, true)
        const blockNum = await helpers.latestBlock()
        await expect(tx)
          .emit(rewardsManager, 'RewardsDenylistUpdated')
          .withArgs(subgraphDeploymentID1, blockNum + 1)
        expect(await rewardsManager.isDenied(subgraphDeploymentID1)).eq(true)
      })

      it('should allow removing subgraph from denylist', async function () {
        await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(oracle.address)

        // First deny the subgraph
        await rewardsManager.connect(oracle).setDenied(subgraphDeploymentID1, true)
        expect(await rewardsManager.isDenied(subgraphDeploymentID1)).eq(true)

        // Then remove from denylist
        const tx = rewardsManager.connect(oracle).setDenied(subgraphDeploymentID1, false)
        await expect(tx).emit(rewardsManager, 'RewardsDenylistUpdated').withArgs(subgraphDeploymentID1, 0)
        expect(await rewardsManager.isDenied(subgraphDeploymentID1)).eq(false)
      })

      it('should be a no-op when denying an already denied subgraph', async function () {
        await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(oracle.address)

        // Deny the subgraph
        await rewardsManager.connect(oracle).setDenied(subgraphDeploymentID1, true)
        expect(await rewardsManager.isDenied(subgraphDeploymentID1)).eq(true)
        const denyBlockBefore = await rewardsManager.denylist(subgraphDeploymentID1)

        // Deny again - should not emit event or change denylist block number
        const tx = rewardsManager.connect(oracle).setDenied(subgraphDeploymentID1, true)
        await expect(tx).not.emit(rewardsManager, 'RewardsDenylistUpdated')

        // State should be unchanged
        expect(await rewardsManager.isDenied(subgraphDeploymentID1)).eq(true)
        const denyBlockAfter = await rewardsManager.denylist(subgraphDeploymentID1)
        expect(denyBlockAfter).eq(denyBlockBefore)
      })

      it('should be a no-op when undenying an already not-denied subgraph', async function () {
        await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(oracle.address)

        // Subgraph is not denied by default
        expect(await rewardsManager.isDenied(subgraphDeploymentID1)).eq(false)

        // Undeny should not emit event
        const tx = rewardsManager.connect(oracle).setDenied(subgraphDeploymentID1, false)
        await expect(tx).not.emit(rewardsManager, 'RewardsDenylistUpdated')

        // State should remain unchanged
        expect(await rewardsManager.isDenied(subgraphDeploymentID1)).eq(false)
        expect(await rewardsManager.denylist(subgraphDeploymentID1)).eq(0)
      })

      it('should reject setMinimumSubgraphSignal if unauthorized', async function () {
        const tx = rewardsManager.connect(indexer1).setMinimumSubgraphSignal(toGRT('1000'))
        await expect(tx).revertedWith('Not authorized')
      })

      it('should allow setMinimumSubgraphSignal from subgraph availability oracle', async function () {
        await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(oracle.address)

        const newMinimumSignal = toGRT('2000')
        const tx = rewardsManager.connect(oracle).setMinimumSubgraphSignal(newMinimumSignal)
        await expect(tx).emit(rewardsManager, 'ParameterUpdated').withArgs('minimumSubgraphSignal')

        expect(await rewardsManager.minimumSubgraphSignal()).eq(newMinimumSignal)
      })

      it('should allow setMinimumSubgraphSignal from governor', async function () {
        const newMinimumSignal = toGRT('3000')
        const tx = rewardsManager.connect(governor).setMinimumSubgraphSignal(newMinimumSignal)
        await expect(tx).emit(rewardsManager, 'ParameterUpdated').withArgs('minimumSubgraphSignal')

        expect(await rewardsManager.minimumSubgraphSignal()).eq(newMinimumSignal)
      })
    })
  })
})

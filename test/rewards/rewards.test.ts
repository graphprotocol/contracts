import { expect } from 'chai'
import { constants, BigNumber, ContractReceipt } from 'ethers'

import { NetworkFixture } from '../lib/fixtures'

import { Curation } from '../../build/types/Curation'
import { EpochManager } from '../../build/types/EpochManager'
import { GraphToken } from '../../build/types/GraphToken'
import { RewardsManager } from '../../build/types/RewardsManager'
import { Staking } from '../../build/types/Staking'

import { BigNumber as BN } from 'bignumber.js'

import {
  advanceBlocks,
  deriveChannelKey,
  getAccounts,
  randomHexBytes,
  latestBlock,
  toBN,
  toGRT,
  formatGRT,
  Account,
  advanceToNextEpoch,
  provider,
  RewardsTracker,
} from '../lib/testHelpers'
import { L1Reservoir } from '../../build/types/L1Reservoir'
import { LogDescription } from 'ethers/lib/utils'

const MAX_PPM = 1000000

const { HashZero, WeiPerEther } = constants

const toRound = (n: BigNumber) => formatGRT(n).split('.')[0]

describe('Rewards', () => {
  let delegator: Account
  let governor: Account
  let curator1: Account
  let curator2: Account
  let indexer1: Account
  let indexer2: Account
  let oracle: Account
  let keeper: Account

  let fixture: NetworkFixture

  let grt: GraphToken
  let curation: Curation
  let epochManager: EpochManager
  let staking: Staking
  let rewardsManager: RewardsManager
  let l1Reservoir: L1Reservoir

  let supplyBeforeDrip: BigNumber
  let dripBlock: BigNumber

  // Derive some channel keys for each indexer used to sign attestations
  const channelKey1 = deriveChannelKey()
  const channelKey2 = deriveChannelKey()

  const subgraphDeploymentID1 = randomHexBytes()
  const subgraphDeploymentID2 = randomHexBytes()

  const allocationID1 = channelKey1.address
  const allocationID2 = channelKey2.address

  const metadata = HashZero

  const ISSUANCE_RATE_PERIODS = 4 // blocks required to issue 0.05% rewards
  const ISSUANCE_RATE_PER_BLOCK = toBN('1000122722344290393') // % increase every block

  // Test accumulated rewards per signal
  const shouldGetNewRewardsPerSignal = async (
    initialSupply: BigNumber,
    nBlocks = ISSUANCE_RATE_PERIODS,
    dripBlock?: BigNumber,
  ) => {
    // -- t0 --
    const tracker = await RewardsTracker.create(initialSupply, ISSUANCE_RATE_PER_BLOCK, dripBlock)
    await tracker.snapshotPerSignal(await grt.balanceOf(curation.address))
    // Jump
    await advanceBlocks(nBlocks)

    // -- t1 --

    // Contract calculation
    const contractAccrued = await rewardsManager.getNewRewardsPerSignal()
    // Local calculation
    const expectedAccrued = await tracker.newRewardsPerSignal(await grt.balanceOf(curation.address))

    // Check
    expect(toRound(contractAccrued)).eq(toRound(expectedAccrued))
    return expectedAccrued
  }

  const findRewardsManagerEvents = (receipt: ContractReceipt): Array<LogDescription> => {
    return receipt.logs
      .map((l) => {
        try {
          return rewardsManager.interface.parseLog(l)
        } catch {
          return null
        }
      })
      .filter((l) => !!l)
  }

  before(async function () {
    ;[delegator, governor, curator1, curator2, indexer1, indexer2, oracle, keeper] =
      await getAccounts()

    fixture = new NetworkFixture()
    ;({ grt, curation, epochManager, staking, rewardsManager, l1Reservoir } = await fixture.load(
      governor.signer,
    ))

    // Distribute test funds
    for (const wallet of [indexer1, indexer2, curator1, curator2]) {
      await grt.connect(governor.signer).mint(wallet.address, toGRT('1000000'))
      await grt.connect(wallet.signer).approve(staking.address, toGRT('1000000'))
      await grt.connect(wallet.signer).approve(curation.address, toGRT('1000000'))
    }
    await l1Reservoir.connect(governor.signer).grantDripPermission(keeper.address)
    await l1Reservoir.connect(governor.signer).initialSnapshot(toBN(0))
    supplyBeforeDrip = await grt.totalSupply()
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('configuration', function () {
    describe('subgraph availability service', function () {
      it('reject set subgraph oracle if unauthorized', async function () {
        const tx = rewardsManager
          .connect(indexer1.signer)
          .setSubgraphAvailabilityOracle(oracle.address)
        await expect(tx).revertedWith('Caller must be Controller governor')
      })

      it('should set subgraph oracle if governor', async function () {
        await rewardsManager.connect(governor.signer).setSubgraphAvailabilityOracle(oracle.address)
        expect(await rewardsManager.subgraphAvailabilityOracle()).eq(oracle.address)
      })

      it('reject to deny subgraph if not the oracle', async function () {
        const tx = rewardsManager.setDenied(subgraphDeploymentID1, true)
        await expect(tx).revertedWith('Caller must be the subgraph availability oracle')
      })

      it('should deny subgraph', async function () {
        await rewardsManager.connect(governor.signer).setSubgraphAvailabilityOracle(oracle.address)

        const tx = rewardsManager.connect(oracle.signer).setDenied(subgraphDeploymentID1, true)
        const blockNum = await latestBlock()
        await expect(tx)
          .emit(rewardsManager, 'RewardsDenylistUpdated')
          .withArgs(subgraphDeploymentID1, blockNum.add(1))
        expect(await rewardsManager.isDenied(subgraphDeploymentID1)).eq(true)
      })

      it('reject deny subgraph w/ many if not the oracle', async function () {
        const deniedSubgraphs = [subgraphDeploymentID1, subgraphDeploymentID2]
        const tx = rewardsManager
          .connect(oracle.signer)
          .setDeniedMany(deniedSubgraphs, [true, true])
        await expect(tx).revertedWith('Caller must be the subgraph availability oracle')
      })

      it('should deny subgraph w/ many', async function () {
        await rewardsManager.connect(governor.signer).setSubgraphAvailabilityOracle(oracle.address)

        const deniedSubgraphs = [subgraphDeploymentID1, subgraphDeploymentID2]
        await rewardsManager.connect(oracle.signer).setDeniedMany(deniedSubgraphs, [true, true])
        expect(await rewardsManager.isDenied(subgraphDeploymentID1)).eq(true)
        expect(await rewardsManager.isDenied(subgraphDeploymentID2)).eq(true)
      })
    })
  })

  context('issuing rewards', async function () {
    interface DelegationParameters {
      indexingRewardCut: BigNumber
      queryFeeCut: BigNumber
      cooldownBlocks: number
    }

    async function setupIndexerAllocation() {
      // Update total signalled
      const signalled1 = toGRT('1500')
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)

      // Allocate
      const tokensToAllocate = toGRT('12500')
      await staking.connect(indexer1.signer).stake(tokensToAllocate)
      await staking
        .connect(indexer1.signer)
        .allocateFrom(
          indexer1.address,
          subgraphDeploymentID1,
          tokensToAllocate,
          allocationID1,
          metadata,
          await channelKey1.generateProof(indexer1.address),
        )
    }

    async function setupIndexerAllocationWithDelegation(
      tokensToDelegate: BigNumber,
      delegationParams: DelegationParameters,
    ) {
      const tokensToAllocate = toGRT('12500')

      // Transfer some funds from the curator, I don't want to mint new tokens
      await grt.connect(curator1.signer).transfer(delegator.address, tokensToDelegate)
      await grt.connect(delegator.signer).approve(staking.address, tokensToDelegate)

      // Stake and set delegation parameters
      await staking.connect(indexer1.signer).stake(tokensToAllocate)
      await staking
        .connect(indexer1.signer)
        .setDelegationParameters(
          delegationParams.indexingRewardCut,
          delegationParams.queryFeeCut,
          delegationParams.cooldownBlocks,
        )

      // Delegate
      await staking.connect(delegator.signer).delegate(indexer1.address, tokensToDelegate)

      // Update total signalled
      const signalled1 = toGRT('1500')
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)

      // Allocate
      await staking
        .connect(indexer1.signer)
        .allocateFrom(
          indexer1.address,
          subgraphDeploymentID1,
          tokensToAllocate,
          allocationID1,
          metadata,
          await channelKey1.generateProof(indexer1.address),
        )
    }

    function calculatedExpectedRewards(
      firstSnapshotBlocks: BN,
      lastSnapshotBlocks: BN,
      allocatedTokens: BN,
    ): BigNumber {
      const issuanceBase = new BN(10004000000)
      const issuanceRate = new BN(ISSUANCE_RATE_PER_BLOCK.toString()).div(1e18)
      // All the rewards in this subgraph go to this allocation.
      // Rewards per token will be (issuanceBase * issuanceRate^nBlocks - issuanceBase) / allocatedTokens
      // The first snapshot is after allocating, that is lastSnapshotBlocks blocks after dripBlock:
      const startRewardsPerToken = issuanceBase
        .times(issuanceRate.pow(firstSnapshotBlocks))
        .minus(issuanceBase)
        .div(allocatedTokens)
      // The final snapshot is when we close the allocation, that happens 8 blocks later:
      const endRewardsPerToken = issuanceBase
        .times(issuanceRate.pow(lastSnapshotBlocks))
        .minus(issuanceBase)
        .div(allocatedTokens)
      // Then our expected rewards are (endRewardsPerToken - startRewardsPerToken) * allocatedTokens.
      return toGRT(
        endRewardsPerToken.minus(startRewardsPerToken).times(allocatedTokens).toPrecision(18),
      )
    }

    beforeEach(async function () {
      // 5% minute rate (4 blocks)
      await l1Reservoir.connect(governor.signer).setIssuanceRate(ISSUANCE_RATE_PER_BLOCK)
      await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)
      dripBlock = await latestBlock()
    })

    describe('getNewRewardsPerSignal', function () {
      it('accrued per signal when no tokens signalled', async function () {
        // When there is no tokens signalled no rewards are accrued
        await advanceToNextEpoch(epochManager)
        const accrued = await rewardsManager.getNewRewardsPerSignal()
        expect(accrued).eq(0)
      })

      it('accrued per signal when tokens signalled', async function () {
        // Update total signalled
        const tokensToSignal = toGRT('1000')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, tokensToSignal, 0)

        // Check
        await shouldGetNewRewardsPerSignal(supplyBeforeDrip, ISSUANCE_RATE_PERIODS, dripBlock)
      })

      it('accrued per signal when signalled tokens w/ many subgraphs', async function () {
        // Update total signalled
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, toGRT('1000'), 0)

        // Check
        await shouldGetNewRewardsPerSignal(supplyBeforeDrip, ISSUANCE_RATE_PERIODS, dripBlock)

        // Update total signalled
        await curation.connect(curator2.signer).mint(subgraphDeploymentID2, toGRT('250'), 0)

        // Check
        await shouldGetNewRewardsPerSignal(supplyBeforeDrip, ISSUANCE_RATE_PERIODS, dripBlock)
      })
    })

    describe('updateAccRewardsPerSignal', function () {
      it('update the accumulated rewards per signal state', async function () {
        const tracker = await RewardsTracker.create(
          supplyBeforeDrip,
          ISSUANCE_RATE_PER_BLOCK,
          dripBlock,
        )
        // Snapshot
        const prevSignal = await grt.balanceOf(curation.address)
        // Update total signalled
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, toGRT('1000'), 0)
        // Minting signal triggers onSubgraphSignalUpgrade before pulling the GRT,
        // so we snapshot using the previous value
        await tracker.snapshotPerSignal(prevSignal)

        // Update
        await rewardsManager.updateAccRewardsPerSignal()
        await tracker.snapshotPerSignal(await grt.balanceOf(curation.address))

        const contractAccrued = await rewardsManager.accRewardsPerSignal()

        // Check
        const blockNum = await latestBlock()
        const expectedAccrued = await tracker.accRewardsPerSignal(
          await grt.balanceOf(curation.address),
          blockNum,
        )
        expect(toRound(contractAccrued)).eq(toRound(expectedAccrued))
      })

      it('update the accumulated rewards per signal state after many blocks', async function () {
        const tracker = await RewardsTracker.create(
          supplyBeforeDrip,
          ISSUANCE_RATE_PER_BLOCK,
          dripBlock,
        )
        // Snapshot
        const prevSignal = await grt.balanceOf(curation.address)
        // Update total signalled
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, toGRT('1000'), 0)
        // Minting signal triggers onSubgraphSignalUpgrade before pulling the GRT,
        // so we snapshot using the previous value
        await tracker.snapshotPerSignal(prevSignal)

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Update
        await rewardsManager.updateAccRewardsPerSignal()
        await tracker.snapshotPerSignal(await grt.balanceOf(curation.address))
        const contractAccrued = await rewardsManager.accRewardsPerSignal()

        const blockNum = await latestBlock()
        const expectedAccrued = await tracker.accRewardsPerSignal(
          await grt.balanceOf(curation.address),
          blockNum.add(0),
        )
        expect(toRound(contractAccrued)).eq(toRound(expectedAccrued))
      })
    })

    describe('getAccRewardsForSubgraph', function () {
      it('accrued for each subgraph', async function () {
        const tracker = await RewardsTracker.create(
          supplyBeforeDrip,
          ISSUANCE_RATE_PER_BLOCK,
          dripBlock,
        )
        // Snapshot
        let prevSignal = await grt.balanceOf(curation.address)
        // Curator1 - Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)
        const sg1Snapshot = await tracker.snapshotPerSignal(prevSignal)

        // Curator2 - Update total signalled
        const signalled2 = toGRT('500')
        prevSignal = await grt.balanceOf(curation.address)
        await curation.connect(curator2.signer).mint(subgraphDeploymentID2, signalled2, 0)
        const sg2Snapshot = await tracker.snapshotPerSignal(prevSignal)

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Calculate rewards
        const rewardsPerSignal = await tracker.accRewardsPerSignal(
          await grt.balanceOf(curation.address),
        )
        const expectedRewardsSG1 = rewardsPerSignal
          .sub(sg1Snapshot)
          .mul(signalled1)
          .div(WeiPerEther)
        const expectedRewardsSG2 = rewardsPerSignal
          .sub(sg2Snapshot)
          .mul(signalled2)
          .div(WeiPerEther)

        // Get rewards from contract
        const contractRewardsSG1 = await rewardsManager.getAccRewardsForSubgraph(
          subgraphDeploymentID1,
        )
        const contractRewardsSG2 = await rewardsManager.getAccRewardsForSubgraph(
          subgraphDeploymentID2,
        )

        // Check
        expect(toRound(expectedRewardsSG1)).eq(toRound(contractRewardsSG1))
        expect(toRound(expectedRewardsSG2)).eq(toRound(contractRewardsSG2))
      })
    })

    describe('onSubgraphSignalUpdate', function () {
      it('update the accumulated rewards for subgraph state', async function () {
        const tracker = await RewardsTracker.create(
          supplyBeforeDrip,
          ISSUANCE_RATE_PER_BLOCK,
          dripBlock,
        )
        // Snapshot
        const prevSignal = await grt.balanceOf(curation.address)
        // Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)
        // Snapshot
        await tracker.snapshotPerSignal(prevSignal)

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Update
        await rewardsManager.onSubgraphSignalUpdate(subgraphDeploymentID1)
        const snapshot = await tracker.snapshotPerSignal(await grt.balanceOf(curation.address))
        // Check
        const contractRewardsSG1 = (await rewardsManager.subgraphs(subgraphDeploymentID1))
          .accRewardsForSubgraph
        const expectedRewardsSG1 = snapshot.mul(signalled1).div(WeiPerEther)
        expect(toRound(expectedRewardsSG1)).eq(toRound(contractRewardsSG1))

        const contractAccrued = await rewardsManager.accRewardsPerSignal()
        const expectedAccrued = await tracker.accRewardsPerSignal(
          await grt.balanceOf(curation.address),
        )
        expect(toRound(expectedAccrued)).eq(toRound(contractAccrued))

        const contractBlockUpdated = await rewardsManager.accRewardsPerSignalLastBlockUpdated()
        const expectedBlockUpdated = await latestBlock()
        expect(expectedBlockUpdated).eq(contractBlockUpdated)
      })
    })

    describe('getAccRewardsPerAllocatedToken', function () {
      it('accrued per allocated token', async function () {
        // Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)

        // Allocate
        const tokensToAllocate = toGRT('12500')
        await staking.connect(indexer1.signer).stake(tokensToAllocate)
        await staking
          .connect(indexer1.signer)
          .allocateFrom(
            indexer1.address,
            subgraphDeploymentID1,
            tokensToAllocate,
            allocationID1,
            metadata,
            await channelKey1.generateProof(indexer1.address),
          )

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Check
        const sg1 = await rewardsManager.subgraphs(subgraphDeploymentID1)
        // We trust this function because it was individually tested in previous test
        const accRewardsForSubgraphSG1 = await rewardsManager.getAccRewardsForSubgraph(
          subgraphDeploymentID1,
        )
        const accruedRewardsSG1 = accRewardsForSubgraphSG1.sub(sg1.accRewardsForSubgraphSnapshot)
        const expectedRewardsAT1 = accruedRewardsSG1.mul(WeiPerEther).div(tokensToAllocate)
        const contractRewardsAT1 = (
          await rewardsManager.getAccRewardsPerAllocatedToken(subgraphDeploymentID1)
        )[0]
        expect(expectedRewardsAT1).eq(contractRewardsAT1)
      })
    })

    describe('onSubgraphAllocationUpdate', function () {
      it('update the accumulated rewards for allocated tokens state', async function () {
        // Update total signalled
        const signalled1 = toGRT('1500')
        // block = dripBlock
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)
        // block  = dripBlock + 1

        // Allocate
        const tokensToAllocate = toGRT('12500')
        await staking.connect(indexer1.signer).stake(tokensToAllocate)
        // block  = dripBlock + 2
        await staking
          .connect(indexer1.signer)
          .allocateFrom(
            indexer1.address,
            subgraphDeploymentID1,
            tokensToAllocate,
            allocationID1,
            metadata,
            await channelKey1.generateProof(indexer1.address),
          )
        // block  = dripBlock + 3
        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)
        // block  = dripBlock + 7

        // Update
        await rewardsManager.onSubgraphAllocationUpdate(subgraphDeploymentID1)
        // block = dripBlock + 8

        // Prepare expected results
        // Expected total rewards:
        // DeltaR_end = supplyBeforeDrip * r ^ 8 - supplyBeforeDrip
        // DeltaR_end = 10004000000 GRT * (1000122722344290393 / 1e18)^8 - 10004000000 GRT = 9825934.397
        // The signal was minted at dripBlock + 1, so:
        // DeltaR_start = supplyBeforeDrip * r ^ 1 - supplyBeforeDrip = 1227714.332

        // And they all go to this subgraph, so subgraph rewards = DeltaR_end - DeltaR_start = 8598220.065
        const expectedSubgraphRewards = toGRT('8598220')

        // The allocation happened at dripBlock + 3, so rewards per allocated token are:
        // ((supplyBeforeDrip * r ^ 8 - supplyBeforeDrip) - (supplyBeforeDrip * r ^ 3 - supplyBeforeDrip)) / 12500 = 491.387
        const expectedRewardsAT = toGRT('491')
        // Check on demand results saved
        const subgraph = await rewardsManager.subgraphs(subgraphDeploymentID1)
        const contractSubgraphRewards = await rewardsManager.getAccRewardsForSubgraph(
          subgraphDeploymentID1,
        )
        const contractRewardsAT = subgraph.accRewardsPerAllocatedToken

        expect(toRound(expectedSubgraphRewards)).eq(toRound(contractSubgraphRewards))
        expect(toRound(expectedRewardsAT)).eq(toRound(contractRewardsAT))
      })
    })

    describe('getRewards', function () {
      it('calculate rewards using the subgraph signalled + allocated tokens', async function () {
        // Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)

        // Allocate
        const tokensToAllocate = toGRT('12500')
        await staking.connect(indexer1.signer).stake(tokensToAllocate)
        await staking
          .connect(indexer1.signer)
          .allocateFrom(
            indexer1.address,
            subgraphDeploymentID1,
            tokensToAllocate,
            allocationID1,
            metadata,
            await channelKey1.generateProof(indexer1.address),
          )

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Rewards
        const contractRewards = await rewardsManager.getRewards(allocationID1)

        // We trust using this function in the test because we tested it
        // standalone in a previous test
        const contractRewardsAT1 = (
          await rewardsManager.getAccRewardsPerAllocatedToken(subgraphDeploymentID1)
        )[0]

        const expectedRewards = contractRewardsAT1.mul(tokensToAllocate).div(WeiPerEther)
        expect(expectedRewards).eq(contractRewards)
      })
    })

    describe('takeAndBurnRewards', function () {
      it('should burn rewards on closed allocation with POI zero', async function () {
        // Align with the epoch boundary
        await epochManager.setEpochLength(10)
        await advanceToNextEpoch(epochManager)

        // Setup
        await setupIndexerAllocation()
        const firstSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())

        // Jump
        await advanceToNextEpoch(epochManager)

        // Before state
        const beforeTokenSupply = await grt.totalSupply()
        const beforeIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)
        const beforeIndexer1Balance = await grt.balanceOf(indexer1.address)
        const beforeStakingBalance = await grt.balanceOf(staking.address)

        // Close allocation with POI zero, which should burn the rewards
        const tx = await staking.connect(indexer1.signer).closeAllocation(allocationID1, HashZero)
        const receipt = await tx.wait()

        const lastSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())

        const expectedIndexingRewards = calculatedExpectedRewards(
          firstSnapshotBlocks,
          lastSnapshotBlocks,
          new BN(12500),
        )

        const log = findRewardsManagerEvents(receipt)[0]
        const event = log.args
        expect(log.name).eq('RewardsBurned')
        expect(event.indexer).eq(indexer1.address)
        expect(event.allocationID).eq(allocationID1)
        expect(event.epoch).eq(await epochManager.currentEpoch())
        expect(toRound(event.amount)).eq(toRound(expectedIndexingRewards))

        // After state
        const afterTokenSupply = await grt.totalSupply()
        const afterIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)
        const afterIndexer1Balance = await grt.balanceOf(indexer1.address)
        const afterStakingBalance = await grt.balanceOf(staking.address)

        // Check that rewards are NOT put into indexer stake
        const expectedIndexerStake = beforeIndexer1Stake

        // Check stake should NOT have increased with the rewards staked
        expect(toRound(afterIndexer1Stake)).eq(toRound(expectedIndexerStake))
        // Check indexer balance remains the same
        expect(afterIndexer1Balance).eq(beforeIndexer1Balance)
        // Check indexing rewards are kept in the staking contract
        expect(toRound(afterStakingBalance)).eq(toRound(beforeStakingBalance))
        // Check that tokens have been burned
        // We divide by 10 to accept numeric errors up to 10 GRT
        expect(toRound(afterTokenSupply.div(10))).eq(
          toRound(beforeTokenSupply.sub(expectedIndexingRewards).div(10)),
        )
      })
    })

    describe('takeRewards', function () {
      it('should distribute rewards on closed allocation and stake', async function () {
        // Align with the epoch boundary
        await epochManager.setEpochLength(10)
        await advanceToNextEpoch(epochManager)

        // Setup
        await setupIndexerAllocation()
        const firstSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())

        // Jump
        await advanceToNextEpoch(epochManager)

        // Before state
        const beforeTokenSupply = await grt.totalSupply()
        const beforeIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)
        const beforeIndexer1Balance = await grt.balanceOf(indexer1.address)
        const beforeStakingBalance = await grt.balanceOf(staking.address)

        // Close allocation. At this point rewards should be collected for that indexer
        const tx = await staking
          .connect(indexer1.signer)
          .closeAllocation(allocationID1, randomHexBytes())
        const receipt = await tx.wait()

        const lastSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())
        const expectedIndexingRewards = calculatedExpectedRewards(
          firstSnapshotBlocks,
          lastSnapshotBlocks,
          new BN(12500),
        )

        const event = findRewardsManagerEvents(receipt)[0].args
        expect(event.indexer).eq(indexer1.address)
        expect(event.allocationID).eq(allocationID1)
        expect(event.epoch).eq(await epochManager.currentEpoch())
        expect(toRound(event.amount)).eq(toRound(expectedIndexingRewards))

        // After state
        const afterTokenSupply = await grt.totalSupply()
        const afterIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)
        const afterIndexer1Balance = await grt.balanceOf(indexer1.address)
        const afterStakingBalance = await grt.balanceOf(staking.address)

        // Check that rewards are put into indexer stake
        const expectedIndexerStake = beforeIndexer1Stake.add(expectedIndexingRewards)

        // Check stake should have increased with the rewards staked
        expect(toRound(afterIndexer1Stake)).eq(toRound(expectedIndexerStake))
        // Check indexer balance remains the same
        expect(afterIndexer1Balance).eq(beforeIndexer1Balance)
        // Check indexing rewards are kept in the staking contract
        expect(toRound(afterStakingBalance)).eq(
          toRound(beforeStakingBalance.add(expectedIndexingRewards)),
        )
        // Check that tokens have NOT been minted
        expect(toRound(afterTokenSupply)).eq(toRound(beforeTokenSupply))
      })

      it('should distribute rewards on closed allocation and send to destination', async function () {
        const destinationAddress = randomHexBytes(20)
        await staking.connect(indexer1.signer).setRewardsDestination(destinationAddress)

        await epochManager.setEpochLength(10)
        // Align with the epoch boundary
        await advanceToNextEpoch(epochManager)
        // Setup
        await setupIndexerAllocation()
        const firstSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())

        // Jump
        await advanceToNextEpoch(epochManager)

        // Before state
        const beforeTokenSupply = await grt.totalSupply()
        const beforeIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)
        const beforeDestinationBalance = await grt.balanceOf(destinationAddress)
        const beforeStakingBalance = await grt.balanceOf(staking.address)

        // Close allocation. At this point rewards should be collected for that indexer
        const tx = await staking
          .connect(indexer1.signer)
          .closeAllocation(allocationID1, randomHexBytes())
        const receipt = await tx.wait()
        const lastSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())
        const event = findRewardsManagerEvents(receipt)[0].args
        expect(event.indexer).eq(indexer1.address)
        expect(event.allocationID).eq(allocationID1)
        expect(event.epoch).eq(await epochManager.currentEpoch())

        const expectedIndexingRewards = calculatedExpectedRewards(
          firstSnapshotBlocks,
          lastSnapshotBlocks,
          new BN(12500),
        )
        expect(toRound(event.amount)).eq(toRound(expectedIndexingRewards))

        // After state
        const afterTokenSupply = await grt.totalSupply()
        const afterIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)
        const afterDestinationBalance = await grt.balanceOf(destinationAddress)
        const afterStakingBalance = await grt.balanceOf(staking.address)

        // Check that rewards are properly assigned
        const expectedIndexerStake = beforeIndexer1Stake

        // Check stake should not have changed
        expect(toRound(afterIndexer1Stake)).eq(toRound(expectedIndexerStake))
        // Check indexing rewards are received by the rewards destination
        expect(toRound(afterDestinationBalance)).eq(
          toRound(beforeDestinationBalance.add(expectedIndexingRewards)),
        )
        // Check indexing rewards were not sent to the staking contract
        expect(afterStakingBalance).eq(beforeStakingBalance)
        // Check that tokens have NOT been minted
        expect(toRound(afterTokenSupply)).eq(toRound(beforeTokenSupply))
      })

      it('should distribute rewards on closed allocation w/delegators', async function () {
        // Setup
        const delegationParams = {
          indexingRewardCut: toBN('823000'), // 82.30%
          queryFeeCut: toBN('80000'), // 8%
          cooldownBlocks: 5,
        }
        const tokensToDelegate = toGRT('2000')
        await epochManager.setEpochLength(10)

        // Align with the epoch boundary
        await advanceToNextEpoch(epochManager)

        // Setup the allocation and delegators
        await setupIndexerAllocationWithDelegation(tokensToDelegate, delegationParams)
        const firstSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())

        // Jump
        await advanceToNextEpoch(epochManager)
        // dripBlock + 13

        // Before state
        const beforeTokenSupply = await grt.totalSupply()
        const beforeDelegationPool = await staking.delegationPools(indexer1.address)
        const beforeIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)

        // Close allocation. At this point rewards should be collected for that indexer
        await staking.connect(indexer1.signer).closeAllocation(allocationID1, randomHexBytes())
        const lastSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())

        // After state
        const afterTokenSupply = await grt.totalSupply()
        const afterDelegationPool = await staking.delegationPools(indexer1.address)
        const afterIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)

        // Check that rewards are put into indexer stake (only indexer cut)
        // Check that rewards are put into delegators pool accordingly

        const expectedIndexingRewards = calculatedExpectedRewards(
          firstSnapshotBlocks,
          lastSnapshotBlocks,
          new BN(14500),
        )

        // Calculate delegators cut
        const indexerRewards = delegationParams.indexingRewardCut
          .mul(expectedIndexingRewards)
          .div(toBN(MAX_PPM))
        // Calculate indexer cut
        const delegatorsRewards = expectedIndexingRewards.sub(indexerRewards)
        // Check
        const expectedIndexerStake = beforeIndexer1Stake.add(indexerRewards)
        const expectedDelegatorsPoolTokens = beforeDelegationPool.tokens.add(delegatorsRewards)
        expect(toRound(afterIndexer1Stake)).eq(toRound(expectedIndexerStake))
        expect(toRound(afterDelegationPool.tokens)).eq(toRound(expectedDelegatorsPoolTokens))
        // Check that tokens have NOT been minted
        expect(toRound(afterTokenSupply)).eq(toRound(beforeTokenSupply))
      })

      it('should deny and burn rewards if subgraph on denylist', async function () {
        // Setup
        // dripBlock (82)
        await epochManager.setEpochLength(10)
        // dripBlock + 1
        await rewardsManager
          .connect(governor.signer)
          .setSubgraphAvailabilityOracle(governor.address)
        // dripBlock + 2
        await rewardsManager.connect(governor.signer).setDenied(subgraphDeploymentID1, true)
        // dripBlock + 3 (epoch boundary!)
        await advanceToNextEpoch(epochManager)
        // dripBlock + 13
        await setupIndexerAllocation()
        const firstSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())

        // Jump
        await advanceToNextEpoch(epochManager)
        // dripBlock + 23

        const supplyBefore = await grt.totalSupply()
        // Close allocation. At this point rewards should be collected for that indexer
        const tx = staking.connect(indexer1.signer).closeAllocation(allocationID1, randomHexBytes())
        await expect(tx).emit(rewardsManager, 'RewardsDenied')
        const lastSnapshotBlocks = new BN((await latestBlock()).sub(dripBlock).toString())
        const receipt = await (await tx).wait()
        const logs = findRewardsManagerEvents(receipt)
        expect(logs.length).to.eq(1)
        expect(logs[0].name).to.eq('RewardsDenied')
        const ev = logs[0].args
        expect(ev.indexer).to.eq(indexer1.address)
        expect(ev.allocationID).to.eq(allocationID1)
        expect(ev.epoch).to.eq(await epochManager.currentEpoch())

        const expectedIndexingRewards = calculatedExpectedRewards(
          firstSnapshotBlocks,
          lastSnapshotBlocks,
          new BN(12500),
        )
        expect(toRound(ev.amount)).to.eq(toRound(expectedIndexingRewards))
        // Check that the rewards were burned
        // We divide by 10 to accept numeric errors up to 10 GRT
        expect(toRound((await grt.totalSupply()).div(10))).to.eq(
          toRound(supplyBefore.sub(expectedIndexingRewards).div(10)),
        )
      })
    })

    describe('edge scenarios', function () {
      it('close allocation on a subgraph that no longer have signal', async function () {
        // Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)

        // Allocate
        const tokensToAllocate = toGRT('12500')
        await staking.connect(indexer1.signer).stake(tokensToAllocate)
        await staking
          .connect(indexer1.signer)
          .allocateFrom(
            indexer1.address,
            subgraphDeploymentID1,
            tokensToAllocate,
            allocationID1,
            metadata,
            await channelKey1.generateProof(indexer1.address),
          )

        // Jump
        await advanceToNextEpoch(epochManager)

        // Remove all signal from the subgraph
        const curatorShares = await curation.getCuratorSignal(
          curator1.address,
          subgraphDeploymentID1,
        )
        await curation.connect(curator1.signer).burn(subgraphDeploymentID1, curatorShares, 0)

        // Close allocation. At this point rewards should be collected for that indexer
        await staking.connect(indexer1.signer).closeAllocation(allocationID1, randomHexBytes())
      })
    })

    describe('multiple allocations', function () {
      it('two allocations in the same block with a GRT burn in the middle should succeed', async function () {
        // If rewards are not monotonically increasing, this can trigger
        // a subtraction overflow error as seen in mainnet tx:
        // 0xb6bf7bbc446720a7409c482d714aebac239dd62e671c3c94f7e93dd3a61835ab
        await advanceToNextEpoch(epochManager)

        // Setup
        await epochManager.setEpochLength(10)

        // Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)

        // Stake
        const tokensToStake = toGRT('12500')
        await staking.connect(indexer1.signer).stake(tokensToStake)

        // Allocate simultaneously, burning in the middle
        const tokensToAlloc = toGRT('5000')
        await provider().send('evm_setAutomine', [false])
        const tx1 = await staking
          .connect(indexer1.signer)
          .allocateFrom(
            indexer1.address,
            subgraphDeploymentID1,
            tokensToAlloc,
            allocationID1,
            metadata,
            await channelKey1.generateProof(indexer1.address),
          )
        const tx2 = await grt.connect(indexer1.signer).burn(toGRT(1))
        const tx3 = await staking
          .connect(indexer1.signer)
          .allocateFrom(
            indexer1.address,
            subgraphDeploymentID1,
            tokensToAlloc,
            allocationID2,
            metadata,
            await channelKey2.generateProof(indexer1.address),
          )

        await provider().send('evm_mine', [])
        await provider().send('evm_setAutomine', [true])

        await expect(tx1).emit(staking, 'AllocationCreated')
        await expect(tx2).emit(grt, 'Transfer')
        await expect(tx3).emit(staking, 'AllocationCreated')
      })
      it('two simultanous-similar allocations should get same amount of rewards', async function () {
        await advanceToNextEpoch(epochManager)

        // Setup
        await epochManager.setEpochLength(10)

        // Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)

        // Stake
        const tokensToStake = toGRT('12500')
        await staking.connect(indexer1.signer).stake(tokensToStake)

        // Allocate simultaneously
        const tokensToAlloc = toGRT('5000')
        const tx1 = await staking.populateTransaction.allocateFrom(
          indexer1.address,
          subgraphDeploymentID1,
          tokensToAlloc,
          allocationID1,
          metadata,
          await channelKey1.generateProof(indexer1.address),
        )
        const tx2 = await staking.populateTransaction.allocateFrom(
          indexer1.address,
          subgraphDeploymentID1,
          tokensToAlloc,
          allocationID2,
          metadata,
          await channelKey2.generateProof(indexer1.address),
        )
        await staking.connect(indexer1.signer).multicall([tx1.data, tx2.data])

        // Jump
        await advanceToNextEpoch(epochManager)

        // Close allocations simultaneously
        const tx3 = await staking.populateTransaction.closeAllocation(
          allocationID1,
          randomHexBytes(),
        )
        const tx4 = await staking.populateTransaction.closeAllocation(
          allocationID2,
          randomHexBytes(),
        )
        const tx5 = await staking.connect(indexer1.signer).multicall([tx3.data, tx4.data])

        // Both allocations should receive the same amount of rewards
        const receipt = await tx5.wait()
        const rewardsMgrEvents = findRewardsManagerEvents(receipt)
        expect(rewardsMgrEvents.length).to.eq(2)
        const event1 = rewardsMgrEvents[0].args
        const event2 = rewardsMgrEvents[1].args
        expect(event1.amount).to.not.eq(toBN(0))
        expect(event1.amount).to.eq(event2.amount)
      })
    })
  })
})

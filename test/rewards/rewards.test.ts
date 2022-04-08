import { expect } from 'chai'
import { constants, BigNumber } from 'ethers'
import { BigNumber as BN } from 'bignumber.js'

import { deployContract } from '../lib/deployment'
import { NetworkFixture } from '../lib/fixtures'

import { Curation } from '../../build/types/Curation'
import { EpochManager } from '../../build/types/EpochManager'
import { GraphToken } from '../../build/types/GraphToken'
import { RewardsManager } from '../../build/types/RewardsManager'
import { RewardsManagerMock } from '../../build/types/RewardsManagerMock'
import { Staking } from '../../build/types/Staking'

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
} from '../lib/testHelpers'

const MAX_PPM = 1000000

const { HashZero, WeiPerEther } = constants

const toRound = (n: BigNumber) => formatGRT(n).split('.')[0]

describe.only('Rewards', () => {
  let delegator: Account
  let governor: Account
  let curator1: Account
  let curator2: Account
  let indexer1: Account
  let indexer2: Account
  let oracle: Account

  let fixture: NetworkFixture

  let grt: GraphToken
  let curation: Curation
  let epochManager: EpochManager
  let staking: Staking
  let rewardsManager: RewardsManager
  let rewardsManagerMock: RewardsManagerMock

  // Derive some channel keys for each indexer used to sign attestations
  const channelKey = deriveChannelKey()

  const subgraphDeploymentID1 = randomHexBytes()
  const subgraphDeploymentID2 = randomHexBytes()

  const allocationID = channelKey.address
  const metadata = HashZero

  const ISSUANCE_RATE_PERIODS = 4 // blocks required to issue 5% rewards
  const ISSUANCE_RATE_PER_BLOCK = toBN('1012270000000000000') // % increase every block

  // Core formula that gets accumulated rewards per signal for a period of time
  const getRewardsPerSignal = (p: BN, r: BN, t: BN, s: BN): string => {
    if (s.eq(0)) {
      return '0'
    }
    return p.times(r.pow(t)).minus(p).div(s).toPrecision(18).toString()
  }

  // Tracks the accumulated rewards as totalSignalled or supply changes across snapshots
  class RewardsTracker {
    totalSupply = BigNumber.from(0)
    totalSignalled = BigNumber.from(0)
    lastUpdatedBlock = BigNumber.from(0)
    accumulated = BigNumber.from(0)

    static async create() {
      const tracker = new RewardsTracker()
      await tracker.snapshot()
      return tracker
    }

    async snapshot() {
      this.accumulated = this.accumulated.add(await this.accrued())
      this.totalSupply = await grt.totalSupply()
      this.totalSignalled = await grt.balanceOf(curation.address)
      this.lastUpdatedBlock = await latestBlock()
      return this
    }

    async elapsedBlocks() {
      const currentBlock = await latestBlock()
      return currentBlock.sub(this.lastUpdatedBlock)
    }

    async accrued() {
      const nBlocks = await this.elapsedBlocks()
      const n = getRewardsPerSignal(
        new BN(this.totalSupply.toString()),
        new BN(ISSUANCE_RATE_PER_BLOCK.toString()).div(1e18),
        new BN(nBlocks.toString()),
        new BN(this.totalSignalled.toString()),
      )
      return toGRT(n)
    }
  }
  interface DelegationParameters {
    indexingRewardCut: BigNumber
    queryFeeCut: BigNumber
    cooldownBlocks: number
  }

  interface DelegationScenario {
    tokensToDelegate: BigNumber
    delegationParams: DelegationParameters
  }

  async function setupIndexingScenario(delegationScenario?: DelegationScenario) {
    // Setup
    await epochManager.setEpochLength(10)

    // Stake
    const tokensToAllocate = toGRT('12500')
    await staking.connect(indexer1.signer).stake(tokensToAllocate)

    // Setup delegation scenario
    if (delegationScenario) {
      const { delegationParams, tokensToDelegate } = delegationScenario
      await staking
        .connect(indexer1.signer)
        .setDelegationParameters(
          delegationParams.indexingRewardCut,
          delegationParams.queryFeeCut,
          delegationParams.cooldownBlocks,
        )

      // Transfer some funds from the curator, we don't want to mint new tokens
      await grt.connect(curator1.signer).transfer(delegator.address, tokensToDelegate)
      await grt.connect(delegator.signer).approve(staking.address, tokensToDelegate)

      // Delegate
      await staking.connect(delegator.signer).delegate(indexer1.address, tokensToDelegate)
    }

    // Update total signalled
    const signalled1 = toGRT('1500')
    await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)

    // Allocate
    return staking
      .connect(indexer1.signer)
      .allocateFrom(
        indexer1.address,
        subgraphDeploymentID1,
        tokensToAllocate,
        allocationID,
        metadata,
        await channelKey.generateProof(indexer1.address),
      )
  }

  // Test accumulated rewards per signal
  const shouldGetNewRewardsPerSignal = async (nBlocks = ISSUANCE_RATE_PERIODS) => {
    // -- t0 --
    const tracker = await RewardsTracker.create()

    // Jump
    await advanceBlocks(nBlocks)

    // -- t1 --

    // Contract calculation
    const contractAccrued = await rewardsManager.getNewRewardsPerSignal()
    // Local calculation
    const expectedAccrued = await tracker.accrued()

    // Check
    expect(toRound(expectedAccrued)).eq(toRound(contractAccrued))
    return expectedAccrued
  }

  before(async function () {
    ;[delegator, governor, curator1, curator2, indexer1, indexer2, oracle] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ grt, curation, epochManager, staking, rewardsManager } = await fixture.load(
      governor.signer,
    ))

    rewardsManagerMock = (await deployContract(
      'RewardsManagerMock',
      governor.signer,
    )) as unknown as RewardsManagerMock

    // 5% minute rate (4 blocks)
    await rewardsManager.connect(governor.signer).setIssuanceRate(ISSUANCE_RATE_PER_BLOCK)

    // Distribute test funds
    for (const wallet of [indexer1, indexer2, curator1, curator2]) {
      await grt.connect(governor.signer).mint(wallet.address, toGRT('1000000'))
      await grt.connect(wallet.signer).approve(staking.address, toGRT('1000000'))
      await grt.connect(wallet.signer).approve(curation.address, toGRT('1000000'))
    }
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('configuration', function () {
    describe('issuance rate update', function () {
      it('reject set issuance rate if unauthorized', async function () {
        const tx = rewardsManager.connect(indexer1.signer).setIssuanceRate(toGRT('1.025'))
        await expect(tx).revertedWith('Caller must be Controller governor')
      })

      it('reject set issuance rate to less than minimum allowed', async function () {
        const newIssuanceRate = toGRT('0.1') // this get a bignumber with 1e17
        const tx = rewardsManager.connect(governor.signer).setIssuanceRate(newIssuanceRate)
        await expect(tx).revertedWith('Issuance rate under minimum allowed')
      })

      it('should set issuance rate to minimum allowed', async function () {
        const newIssuanceRate = toGRT('1') // this get a bignumber with 1e18
        await rewardsManager.connect(governor.signer).setIssuanceRate(newIssuanceRate)
        expect(await rewardsManager.issuanceRate()).eq(newIssuanceRate)
      })

      it('should set issuance rate', async function () {
        const newIssuanceRate = toGRT('1.025')
        await rewardsManager.connect(governor.signer).setIssuanceRate(newIssuanceRate)
        expect(await rewardsManager.issuanceRate()).eq(newIssuanceRate)
        expect(await rewardsManager.accRewardsPerSignalLastBlockUpdated()).eq(await latestBlock())
      })
    })

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
    beforeEach(async function () {
      // 5% minute rate (4 blocks)
      await rewardsManager.connect(governor.signer).setIssuanceRate(ISSUANCE_RATE_PER_BLOCK)
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
        await shouldGetNewRewardsPerSignal()
      })

      it('accrued per signal when signalled tokens w/ many subgraphs', async function () {
        // Update total signalled
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, toGRT('1000'), 0)

        // Check
        await shouldGetNewRewardsPerSignal()

        // Update total signalled
        await curation.connect(curator2.signer).mint(subgraphDeploymentID2, toGRT('250'), 0)

        // Check
        await shouldGetNewRewardsPerSignal()
      })
    })

    describe('updateAccRewardsPerSignal', function () {
      it('update the accumulated rewards per signal state', async function () {
        // Update total signalled
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, toGRT('1000'), 0)
        // Snapshot
        const tracker = await RewardsTracker.create()

        // Update
        await rewardsManager.updateAccRewardsPerSignal()
        const contractAccrued = await rewardsManager.accRewardsPerSignal()

        // Check
        const expectedAccrued = await tracker.accrued()
        expect(toRound(expectedAccrued)).eq(toRound(contractAccrued))
      })

      it('update the accumulated rewards per signal state after many blocks', async function () {
        // Update total signalled
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, toGRT('1000'), 0)
        // Snapshot
        const tracker = await RewardsTracker.create()

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Update
        await rewardsManager.updateAccRewardsPerSignal()
        const contractAccrued = await rewardsManager.accRewardsPerSignal()

        // Check
        const expectedAccrued = await tracker.accrued()
        expect(toRound(expectedAccrued)).eq(toRound(contractAccrued))
      })
    })

    describe('getAccRewardsForSubgraph', function () {
      it('accrued for each subgraph', async function () {
        // Curator1 - Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)
        const tracker1 = await RewardsTracker.create()

        // Curator2 - Update total signalled
        const signalled2 = toGRT('500')
        await curation.connect(curator2.signer).mint(subgraphDeploymentID2, signalled2, 0)

        // Snapshot
        const tracker2 = await RewardsTracker.create()
        await tracker1.snapshot()

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Snapshot
        await tracker1.snapshot()
        await tracker2.snapshot()

        // Calculate rewards
        const rewardsPerSignal1 = await tracker1.accumulated
        const rewardsPerSignal2 = await tracker2.accumulated
        const expectedRewardsSG1 = rewardsPerSignal1.mul(signalled1).div(WeiPerEther)
        const expectedRewardsSG2 = rewardsPerSignal2.mul(signalled2).div(WeiPerEther)

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
        // Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1, 0)
        // Snapshot
        const tracker1 = await RewardsTracker.create()

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Update
        await rewardsManager.onSubgraphSignalUpdate(subgraphDeploymentID1)

        // Check
        const contractRewardsSG1 = (await rewardsManager.subgraphs(subgraphDeploymentID1))
          .accRewardsForSubgraph
        const rewardsPerSignal1 = await tracker1.accrued()
        const expectedRewardsSG1 = rewardsPerSignal1.mul(signalled1).div(WeiPerEther)
        expect(toRound(expectedRewardsSG1)).eq(toRound(contractRewardsSG1))

        const contractAccrued = await rewardsManager.accRewardsPerSignal()
        const expectedAccrued = await tracker1.accrued()
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
            allocationID,
            metadata,
            await channelKey.generateProof(indexer1.address),
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
            allocationID,
            metadata,
            await channelKey.generateProof(indexer1.address),
          )

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Update
        await rewardsManager.onSubgraphAllocationUpdate(subgraphDeploymentID1)

        // Check on demand results saved
        const subgraph = await rewardsManager.subgraphs(subgraphDeploymentID1)
        const contractSubgraphRewards = await rewardsManager.getAccRewardsForSubgraph(
          subgraphDeploymentID1,
        )
        const contractRewardsAT = subgraph.accRewardsPerAllocatedToken

        // Rewards accrued per block at the issuance rate is calculated by:
        // (totalSupply * issuanceRate^nBlocks - totalSupply)
        // 7 blocks accrued after signaling
        // rewards = (10004000000 * 1.01227 ** 7 - 10004000000) = 891527118.49
        const expectedSubgraphRewards = toGRT('891527118')
        const expectedRewardsAT = toGRT('51561')
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
            allocationID,
            metadata,
            await channelKey.generateProof(indexer1.address),
          )

        // Jump
        await advanceBlocks(ISSUANCE_RATE_PERIODS)

        // Rewards
        const contractRewards = await rewardsManager.getRewards(allocationID)

        // We trust using this function in the test because we tested it
        // standalone in a previous test
        const contractRewardsAT1 = (
          await rewardsManager.getAccRewardsPerAllocatedToken(subgraphDeploymentID1)
        )[0]

        const expectedRewards = contractRewardsAT1.mul(tokensToAllocate).div(WeiPerEther)
        expect(expectedRewards).eq(contractRewards)
      })
    })

    describe('takeRewards', function () {
      it('should mint and store indexing rewards on closed allocation', async function () {
        // Align with the epoch boundary
        await advanceToNextEpoch(epochManager)

        // Setup
        await setupIndexingScenario()

        // Jump
        await advanceToNextEpoch(epochManager)

        // Before state
        const beforeTokenSupply = await grt.totalSupply()
        const beforeIndexer1Balance = await grt.balanceOf(indexer1.address)
        const beforeStakingBalance = await grt.balanceOf(staking.address)

        // All the rewards in this subgraph go to this allocation.
        // Rewards per token will be (totalSupply * issuanceRate^nBlocks - totalSupply) / allocatedTokens
        // The first snapshot is after allocating, that is 1 blocks after the signal is minted:
        // startRewardsPerToken = (10004000000 * 1.01227 ^ 1 - 10004000000) / 12500 = 9819.92
        // The final snapshot is when we close the allocation, that happens 9 blocks later:
        // endRewardsPerToken = (10004000000 * 1.01227 ^ 8 - 10004000000) / 12500 = 82017.21
        // Then our expected rewards are (endRewardsPerToken - startRewardsPerToken) * 12500
        const expectedIndexingRewards = toGRT('902466156')

        // Close allocation. At this point rewards should be collected for that indexer
        const tx = await staking
          .connect(indexer1.signer)
          .closeAllocation(allocationID, randomHexBytes())

        // Check event
        const receipt = await tx.wait()
        const event = rewardsManager.interface.parseLog(receipt.logs[1]).args
        expect(event.indexer).eq(indexer1.address)
        expect(event.allocationID).eq(allocationID)
        expect(event.epoch).eq(await epochManager.currentEpoch())
        expect(toRound(event.amount)).eq(toRound(expectedIndexingRewards))

        // After state
        const afterTokenSupply = await grt.totalSupply()
        const afterIndexer1Balance = await grt.balanceOf(indexer1.address)
        const afterStakingBalance = await grt.balanceOf(staking.address)
        const afterAlloc = await staking.allocations(allocationID)
        const afterIndexer1Rewards = afterAlloc.indexingRewards

        // Check that rewards are put into indexer stake
        const expectedTokenSupply = beforeTokenSupply.add(expectedIndexingRewards)
        // Check rewards accrued are stored in the allocation
        expect(toRound(afterIndexer1Rewards)).eq(toRound(expectedIndexingRewards))
        // Check indexer balance remains the same
        expect(afterIndexer1Balance).eq(beforeIndexer1Balance)
        // Check indexing rewards are kept in the staking contract
        expect(toRound(afterStakingBalance)).eq(
          toRound(beforeStakingBalance.add(expectedIndexingRewards)),
        )
        // Check that tokens have been minted
        expect(toRound(afterTokenSupply)).eq(toRound(expectedTokenSupply))
      })

      it('should deny rewards if subgraph on denylist', async function () {
        // Setup
        await rewardsManager
          .connect(governor.signer)
          .setSubgraphAvailabilityOracle(governor.address)
        await rewardsManager.connect(governor.signer).setDenied(subgraphDeploymentID1, true)
        await setupIndexingScenario()

        // Jump
        await advanceToNextEpoch(epochManager)

        // Close allocation. At this point rewards should be collected for that indexer
        const tx = staking.connect(indexer1.signer).closeAllocation(allocationID, randomHexBytes())
        await expect(tx)
          .emit(rewardsManager, 'RewardsDenied')
          .withArgs(indexer1.address, allocationID, await epochManager.currentEpoch())

        // After state
        const alloc = await staking.allocations(allocationID)

        // Check
        await expect(alloc.indexingRewards).eq(0) // should not have accrued any reward
      })

      describe('should distribute rewards when claiming rebate', async function () {
        it('with no delegators', async function () {
          // TODO: we need to change this to test the rewards are sent to the destination only after rebate claim

          const destinationAddress = randomHexBytes(20)
          await staking.connect(indexer1.signer).setRewardsDestination(destinationAddress)

          // Align with the epoch boundary
          await advanceToNextEpoch(epochManager)

          // Setup
          await setupIndexingScenario()

          // Jump
          await advanceToNextEpoch(epochManager)

          // Close allocation, at this point rewards should be assigned to indexer
          await staking.connect(indexer1.signer).closeAllocation(allocationID, randomHexBytes())

          // Jump
          await advanceToNextEpoch(epochManager)

          // Before state
          const beforeIndexerStake = await staking.getIndexerStakedTokens(indexer1.address)
          const beforeDestinationBalance = await grt.balanceOf(destinationAddress)
          const beforeStakingBalance = await grt.balanceOf(staking.address)
          const beforeIndexingRewards = (await staking.allocations(allocationID)).indexingRewards

          const tx = await staking.claim(allocationID)
          // TODO: read event data and ensure it is ok

          // After state
          const afterIndexerStake = await staking.getIndexerStakedTokens(indexer1.address)
          const afterDestinationBalance = await grt.balanceOf(destinationAddress)
          const afterStakingBalance = await grt.balanceOf(staking.address)
        })

        it('should distribute rewards when claiming rebate (with delegators)', async function () {
          // Setup
          const delegationParams = {
            indexingRewardCut: toBN('823000'), // 82.30%
            queryFeeCut: toBN('80000'), // 8%
            cooldownBlocks: 5,
          }
          const tokensToDelegate = toGRT('2000')

          // Align with the epoch boundary
          await advanceToNextEpoch(epochManager)
          // Setup the allocation and delegators
          await setupIndexingScenario({ tokensToDelegate, delegationParams })

          // Jump
          await advanceToNextEpoch(epochManager)

          // Before state
          const beforeTokenSupply = await grt.totalSupply()
          const beforeDelegationPool = await staking.delegationPools(indexer1.address)
          const beforeIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)

          // Close allocation. At this point rewards should be collected for that indexer
          await staking.connect(indexer1.signer).closeAllocation(allocationID, randomHexBytes())

          // After state
          const afterTokenSupply = await grt.totalSupply()
          const afterDelegationPool = await staking.delegationPools(indexer1.address)
          const afterIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)

          // Check that rewards are put into indexer stake (only indexer cut)
          // Check that rewards are put into delegators pool accordingly

          // All the rewards in this subgraph go to this allocation.
          // Rewards per token will be (totalSupply * issuanceRate^nBlocks - totalSupply) / allocatedTokens
          // The first snapshot is after allocating, that is 2 blocks after the signal is minted:
          // startRewardsPerToken = (10004000000 * 1.01227 ^ 2 - 10004000000) / 14500 = 8466.995
          // The final snapshot is when we close the allocation, that happens 4 blocks later:
          // endRewardsPerToken = (10004000000 * 1.01227 ^ 4 - 10004000000) / 14500 = 34496.55
          // Then our expected rewards are (endRewardsPerToken - startRewardsPerToken) * 14500.
          const expectedIndexingRewards = toGRT('377428566.77')
          // Calculate delegators cut
          const indexerRewards = delegationParams.indexingRewardCut
            .mul(expectedIndexingRewards)
            .div(toBN(MAX_PPM))
          // Calculate indexer cut
          const delegatorsRewards = expectedIndexingRewards.sub(indexerRewards)
          // Check
          const expectedIndexerStake = beforeIndexer1Stake.add(indexerRewards)
          const expectedDelegatorsPoolTokens = beforeDelegationPool.tokens.add(delegatorsRewards)
          const expectedTokenSupply = beforeTokenSupply.add(expectedIndexingRewards)
          expect(toRound(afterIndexer1Stake)).eq(toRound(expectedIndexerStake))
          expect(toRound(afterDelegationPool.tokens)).eq(toRound(expectedDelegatorsPoolTokens))
          // Check that tokens have been minted
          expect(toRound(afterTokenSupply)).eq(toRound(expectedTokenSupply))
        })
      })
    })
  })

  describe('pow', function () {
    it('exponentiation works under normal boundaries (annual rate from 1% to 700%, 90 days period)', async function () {
      const baseRatio = toGRT('0.000000004641377923') // 1% annual rate
      const timePeriods = (60 * 60 * 24 * 10) / 15 // 90 days in blocks
      for (let i = 0; i < 50; i = i + 4) {
        const r = baseRatio.mul(i * 4).add(toGRT('1'))
        const h = await rewardsManagerMock.pow(r, timePeriods, toGRT('1'))
        console.log('\tr:', formatGRT(r), '=> c:', formatGRT(h))
      }
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
          allocationID,
          metadata,
          await channelKey.generateProof(indexer1.address),
        )

      // Jump
      await advanceToNextEpoch(epochManager)

      // Remove all signal from the subgraph
      const curatorShares = await curation.getCuratorSignal(curator1.address, subgraphDeploymentID1)
      await curation.connect(curator1.signer).burn(subgraphDeploymentID1, curatorShares, 0)

      // Close allocation. At this point rewards should be collected for that indexer
      await staking.connect(indexer1.signer).closeAllocation(allocationID, randomHexBytes())
    })
  })
})

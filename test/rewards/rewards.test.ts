import { expect } from 'chai'
import { constants, BigNumber } from 'ethers'

import { NetworkFixture } from '../lib/fixtures'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { RewardsManager } from '../../build/typechain/contracts/RewardsManager'
import { Staking } from '../../build/typechain/contracts/Staking'

import {
  advanceBlocks,
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

const toFloat = (n: BigNumber) => parseFloat(formatGRT(n))
const toRound = (n: BigNumber) => Math.round(toFloat(n))

describe('Rewards', () => {
  let delegator: Account
  let governor: Account
  let curator1: Account
  let curator2: Account
  let indexer1: Account
  let indexer2: Account
  let assetHolder: Account
  let oracle: Account

  let fixture: NetworkFixture

  let grt: GraphToken
  let curation: Curation
  let epochManager: EpochManager
  let staking: Staking
  let rewardsManager: RewardsManager

  const subgraphDeploymentID1 = randomHexBytes()
  const subgraphDeploymentID2 = randomHexBytes()
  const allocationID = '0x6367E9dD7641e0fF221740b57B8C730031d72530'
  const metadata = HashZero

  const ISSUANCE_RATE_PERIODS = 4 // blocks required to issue 5% rewards
  const ISSUANCE_RATE_PER_BLOCK = toBN('1012272234429039270') // % increase every block

  // Core formula that gets accumulated rewards per signal for a period of time
  const getRewardsPerSignal = (p: BigNumber, r: BigNumber, t: BigNumber, s: BigNumber): number => {
    if (!toFloat(s)) return 0
    return (toRound(p) * toFloat(r) ** t.toNumber() - toFloat(p)) / toFloat(s)
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
      this.accumulated = this.accumulated.add(await this.accruedGRT())
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
      return getRewardsPerSignal(
        this.totalSupply,
        ISSUANCE_RATE_PER_BLOCK,
        nBlocks,
        this.totalSignalled,
      )
    }

    async accruedGRT() {
      const n = await this.accrued()
      return toGRT(n.toString())
    }

    async accruedRounded() {
      return Math.round(await this.accrued())
    }
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
    const expectedAccrued = await tracker.accruedRounded()

    // Check
    expect(expectedAccrued).eq(toRound(contractAccrued))
    return expectedAccrued
  }

  before(async function () {
    ;[
      delegator,
      governor,
      curator1,
      curator2,
      indexer1,
      indexer2,
      assetHolder,
      oracle,
    ] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ grt, curation, epochManager, staking, rewardsManager } = await fixture.load(
      governor.signer,
    ))

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

  describe('issuance rate update', function () {
    it('reject set issuance rate if unauthorized', async function () {
      const tx = rewardsManager.connect(indexer1.signer).setIssuanceRate(toGRT('1.025'))
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('should set issuance rate', async function () {
      // Should be initially zero
      expect(await rewardsManager.issuanceRate()).eq(ISSUANCE_RATE_PER_BLOCK)

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
      const tx = rewardsManager.connect(oracle.signer).setDeniedMany(deniedSubgraphs, [true, true])
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
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, tokensToSignal)

      // Check
      await shouldGetNewRewardsPerSignal()
    })

    it('accrued per signal when signalled tokens w/ many subgraphs', async function () {
      // Update total signalled
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, toGRT('1000'))

      // Check
      await shouldGetNewRewardsPerSignal()

      // Update total signalled
      await curation.connect(curator2.signer).mint(subgraphDeploymentID2, toGRT('250'))

      // Check
      await shouldGetNewRewardsPerSignal()
    })
  })

  describe('updateAccRewardsPerSignal', function () {
    it('update the accumulated rewards per signal state', async function () {
      // Update total signalled
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, toGRT('1000'))
      // Snapshot
      const tracker = await RewardsTracker.create()

      // Update
      await rewardsManager.updateAccRewardsPerSignal()
      const contractAccrued = await rewardsManager.accRewardsPerSignal()

      // Check
      const expectedAccrued = await tracker.accruedRounded()
      expect(expectedAccrued).eq(toRound(contractAccrued))
    })

    it('update the accumulated rewards per signal state after many blocks', async function () {
      // Update total signalled
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, toGRT('1000'))
      // Snapshot
      const tracker = await RewardsTracker.create()

      // Jump
      await advanceBlocks(ISSUANCE_RATE_PERIODS)

      // Update
      await rewardsManager.updateAccRewardsPerSignal()
      const contractAccrued = await rewardsManager.accRewardsPerSignal()

      // Check
      const expectedAccrued = await tracker.accruedRounded()
      expect(expectedAccrued).eq(toRound(contractAccrued))
    })
  })

  describe('getAccRewardsForSubgraph', function () {
    it('accrued for each subgraph', async function () {
      // Curator1 - Update total signalled
      const signalled1 = toGRT('1500')
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1)
      const tracker1 = await RewardsTracker.create()

      // Curator2 - Update total signalled
      const signalled2 = toGRT('500')
      await curation.connect(curator2.signer).mint(subgraphDeploymentID2, signalled2)

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
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1)
      // Snapshot
      const tracker1 = await RewardsTracker.create()

      // Jump
      await advanceBlocks(ISSUANCE_RATE_PERIODS)

      // Update
      await rewardsManager.onSubgraphSignalUpdate(subgraphDeploymentID1)

      // Check
      const contractRewardsSG1 = (await rewardsManager.subgraphs(subgraphDeploymentID1))
        .accRewardsForSubgraph
      const rewardsPerSignal1 = await tracker1.accruedGRT()
      const expectedRewardsSG1 = rewardsPerSignal1.mul(signalled1).div(WeiPerEther)
      expect(toRound(expectedRewardsSG1)).eq(toRound(contractRewardsSG1))

      const contractAccrued = await rewardsManager.accRewardsPerSignal()
      const expectedAccrued = await tracker1.accruedRounded()
      expect(expectedAccrued).eq(toRound(contractAccrued))

      const contractBlockUpdated = await rewardsManager.accRewardsPerSignalLastBlockUpdated()
      const expectedBlockUpdated = await latestBlock()
      expect(expectedBlockUpdated).eq(contractBlockUpdated)
    })
  })

  describe('getAccRewardsPerAllocatedToken', function () {
    it('accrued per allocated token', async function () {
      // Update total signalled
      const signalled1 = toGRT('1500')
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1)

      // Allocate
      const tokensToAllocate = toGRT('12500')
      await staking.connect(indexer1.signer).stake(tokensToAllocate)
      await staking
        .connect(indexer1.signer)
        .allocate(
          subgraphDeploymentID1,
          tokensToAllocate,
          allocationID,
          assetHolder.address,
          metadata,
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
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1)

      // Allocate
      const tokensToAllocate = toGRT('12500')
      await staking.connect(indexer1.signer).stake(tokensToAllocate)
      await staking
        .connect(indexer1.signer)
        .allocate(
          subgraphDeploymentID1,
          tokensToAllocate,
          allocationID,
          assetHolder.address,
          metadata,
        )

      // Jump
      await advanceBlocks(ISSUANCE_RATE_PERIODS)

      // Prepare expected results
      // NOTE: calculated the expected result manually as the above code has 1 off block difference
      // replace with a RewardsManagerMock
      const expectedSubgraphRewards = 891695471
      const expectedRewardsAT = 51572

      // Update
      await rewardsManager.onSubgraphAllocationUpdate(subgraphDeploymentID1)

      // Check on demand results saved
      const subgraph = await rewardsManager.subgraphs(subgraphDeploymentID1)
      const contractSubgraphRewards = await rewardsManager.getAccRewardsForSubgraph(
        subgraphDeploymentID1,
      )
      const contractRewardsAT = subgraph.accRewardsPerAllocatedToken

      expect(expectedSubgraphRewards).eq(toRound(contractSubgraphRewards))
      expect(expectedRewardsAT).eq(toRound(contractRewardsAT))
    })
  })

  describe('getRewards', function () {
    it('calculate rewards using the subgraph signalled + allocated tokens', async function () {
      // Update total signalled
      const signalled1 = toGRT('1500')
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1)

      // Allocate
      const tokensToAllocate = toGRT('12500')
      await staking.connect(indexer1.signer).stake(tokensToAllocate)
      await staking
        .connect(indexer1.signer)
        .allocate(
          subgraphDeploymentID1,
          tokensToAllocate,
          allocationID,
          assetHolder.address,
          metadata,
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
    interface DelegationParameters {
      indexingRewardCut: BigNumber
      queryFeeCut: BigNumber
      cooldownBlocks: number
    }

    async function setupIndexerDelegation(
      tokensToDelegate: BigNumber,
      delegationParams: DelegationParameters,
    ) {
      // Transfer some funds from the curator, I don't want to mint new tokens
      await grt.connect(curator1.signer).transfer(delegator.address, tokensToDelegate)
      await grt.connect(delegator.signer).approve(staking.address, tokensToDelegate)

      // Delegate
      await staking
        .connect(indexer1.signer)
        .setDelegationParameters(
          delegationParams.indexingRewardCut,
          delegationParams.queryFeeCut,
          delegationParams.cooldownBlocks,
        )
      await staking.connect(delegator.signer).delegate(indexer1.address, tokensToDelegate)
    }

    async function setupIndexerAllocation() {
      // Setup
      await epochManager.setEpochLength(10)

      // Update total signalled
      const signalled1 = toGRT('1500')
      await curation.connect(curator1.signer).mint(subgraphDeploymentID1, signalled1)

      // Allocate
      const tokensToAllocate = toGRT('12500')
      await staking.connect(indexer1.signer).stake(tokensToAllocate)
      await staking
        .connect(indexer1.signer)
        .allocate(
          subgraphDeploymentID1,
          tokensToAllocate,
          allocationID,
          assetHolder.address,
          metadata,
        )
    }

    it('should distribute rewards on closed allocation', async function () {
      // Setup
      await setupIndexerAllocation()

      // Jump
      await advanceBlocks(await epochManager.epochLength())

      // Before state
      const beforeTokenSupply = await grt.totalSupply()
      const beforeIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)

      const expectedIndexingRewards = toGRT('1471954234')

      // Close allocation. At this point rewards should be collected for that indexer
      const tx = await staking
        .connect(indexer1.signer)
        .closeAllocation(allocationID, randomHexBytes())
      const receipt = await tx.wait()
      const event = rewardsManager.interface.parseLog(receipt.logs[1]).args
      expect(event.indexer).eq(indexer1.address)
      expect(event.allocationID).eq(allocationID)
      expect(event.epoch).eq(await epochManager.currentEpoch())
      expect(toRound(event.amount)).eq(toRound(expectedIndexingRewards))

      // After state
      const afterTokenSupply = await grt.totalSupply()
      const afterIndexer1Stake = await staking.getIndexerStakedTokens(indexer1.address)

      // Check that rewards are put into indexer stake
      // NOTE: calculated manually on a spreadsheet
      const expectedIndexerStake = beforeIndexer1Stake.add(expectedIndexingRewards)
      const expectedTokenSupply = beforeTokenSupply.add(expectedIndexingRewards)
      // Check
      expect(toRound(afterIndexer1Stake)).eq(toRound(expectedIndexerStake))
      // Check that tokens have been minted
      expect(toRound(afterTokenSupply)).eq(toRound(expectedTokenSupply))
    })

    it('should distribute rewards on closed allocation w/delegators', async function () {
      // Setup
      const delegationParams = {
        indexingRewardCut: toBN('50000'), // 5%
        queryFeeCut: toBN('80000'), // 8%
        cooldownBlocks: 5,
      }
      const tokensToDelegate = toGRT('2000')

      await setupIndexerDelegation(tokensToDelegate, delegationParams)
      await setupIndexerAllocation()

      // Jump
      await advanceBlocks(await epochManager.epochLength())

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
      // NOTE: calculated manually on a spreadsheet
      const expectedIndexingRewards = toGRT('1471954234')
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

    it('should deny rewards if subgraph on denylist', async function () {
      // Setup
      await rewardsManager.connect(governor.signer).setSubgraphAvailabilityOracle(governor.address)
      await rewardsManager.connect(governor.signer).setDenied(subgraphDeploymentID1, true)
      await setupIndexerAllocation()

      // Jump
      await advanceBlocks(await epochManager.epochLength())

      // Close allocation. At this point rewards should be collected for that indexer
      const tx = staking.connect(indexer1.signer).closeAllocation(allocationID, randomHexBytes())
      await expect(tx)
        .emit(rewardsManager, 'RewardsDenied')
        .withArgs(indexer1.address, allocationID, await epochManager.currentEpoch())
    })
  })
})

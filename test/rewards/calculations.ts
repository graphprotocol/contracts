import { expect } from 'chai'
import { constants, BigNumber, Event, ethers } from 'ethers'

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

// TODO: enforcer
// TODO: issuance rate

const ROUND_PRECISION = 8
const toRounded = (n: BigNumber) => parseFloat(formatGRT(n)).toPrecision(ROUND_PRECISION)
const toFloat = (n: BigNumber) => parseFloat(formatGRT(n))

describe('Rewards:Calculations', () => {
  let me: Account
  let governor: Account
  let curator1: Account
  let curator2: Account
  let indexer1: Account
  let indexer2: Account
  let assetHolder: Account

  let fixture: NetworkFixture

  let grt: GraphToken
  let curation: Curation
  let epochManager: EpochManager
  let staking: Staking
  let rewardsManager: RewardsManager

  const subgraphDeploymentID1 = randomHexBytes()
  const subgraphDeploymentID2 = randomHexBytes()
  const allocationID = '0x6367E9dD7641e0fF221740b57B8C730031d72530'
  const channelPubKey =
    '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'

  const ISSUANCE_RATE_DECIMALS = ethers.constants.WeiPerEther
  const ISSUANCE_RATE_PERIODS = 4 // blocks required to issue 5% rewards
  const ISSUANCE_RATE_PER_BLOCK = toBN('1012272234429039270') // % increase every block
  const ISSUANCE_RATE_PER_PERIOD = toBN('1050000000000000000') // % increase every 4 blocks (5%)

  // Core formula that gets accumulated rewards per signal for a period of time
  const getRewardsPerSignal = (p: BigNumber, r: BigNumber, t: BigNumber, s: BigNumber): number => {
    if (!toFloat(s)) return 0
    return (toFloat(p) * toFloat(r) ** t.toNumber() - toFloat(p)) / toFloat(s)
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
      this.totalSignalled = await curation.totalTokens()
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
      const n = await this.accrued()
      return n.toPrecision(ROUND_PRECISION)
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
    const contractAccrued = toRounded(await rewardsManager.getNewRewardsPerSignal())

    // Local calculation
    const expectedAccrued = await tracker.accruedRounded()

    // Check
    expect(expectedAccrued).eq(contractAccrued)

    return expectedAccrued
  }

  before(async function () {
    ;[me, governor, curator1, curator2, indexer1, indexer2, assetHolder] = await getAccounts()

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
      const contractAccrued = toRounded(await rewardsManager.accRewardsPerSignal())

      // Check
      const expectedAccrued = await tracker.accruedRounded()
      expect(expectedAccrued).eq(contractAccrued)
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
      const contractAccrued = toRounded(await rewardsManager.accRewardsPerSignal())

      // Check
      const expectedAccrued = await tracker.accruedRounded()
      expect(expectedAccrued).eq(contractAccrued)
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
      const expectedRewardsSG1 = toRounded(
        rewardsPerSignal1.mul(signalled1).div(constants.WeiPerEther),
      )
      const expectedRewardsSG2 = toRounded(
        rewardsPerSignal2.mul(signalled2).div(constants.WeiPerEther),
      )

      // Get rewards from contract
      const contractRewardsSG1 = toRounded(
        await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID1),
      )
      const contractRewardsSG2 = toRounded(
        await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID2),
      )

      // Check
      expect(expectedRewardsSG1).eq(contractRewardsSG1)
      expect(expectedRewardsSG2).eq(contractRewardsSG2)
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
      const contractRewardsSG1 = toRounded(
        (await rewardsManager.subgraphs(subgraphDeploymentID1)).accRewardsForSubgraph,
      )
      const rewardsPerSignal1 = await tracker1.accruedGRT()
      const expectedRewardsSG1 = toRounded(
        rewardsPerSignal1.mul(signalled1).div(constants.WeiPerEther),
      )
      expect(expectedRewardsSG1).eq(contractRewardsSG1)

      const contractAccrued = toRounded(await rewardsManager.accRewardsPerSignal())
      const expectedAccrued = await tracker1.accruedRounded()
      expect(expectedAccrued).eq(contractAccrued)

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
          channelPubKey,
          assetHolder.address,
          toGRT('0.1'),
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
      const expectedRewardsAT1 = accruedRewardsSG1.mul(constants.WeiPerEther).div(tokensToAllocate)
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
          channelPubKey,
          assetHolder.address,
          toGRT('0.1'),
        )

      // Jump
      await advanceBlocks(ISSUANCE_RATE_PERIODS)

      // Prepare expected results
      // const sg1 = await rewardsManager.subgraphs(subgraphDeploymentID1)
      // // We trust this function because it was individually tested in previous test
      // const accRewardsForSubgraphSG1 = await rewardsManager.getAccRewardsForSubgraph(
      //   subgraphDeploymentID1,
      // )
      // const accruedRewardsSG1 = accRewardsForSubgraphSG1.sub(sg1.accRewardsForSubgraphSnapshot)
      // const expectedRewardsAT1 = accruedRewardsSG1.mul(constants.WeiPerEther).div(tokensToAllocate)

      // NOTE: calculated the expected result manually as the above code has 1 off block difference
      // replace with a RewardsManagerMock
      const expectedRewardsAT1 = '72171474970536879840'

      // Update
      await rewardsManager.onSubgraphAllocationUpdate(subgraphDeploymentID1)

      // Check on demand results saved
      const updatedSG1 = await rewardsManager.subgraphs(subgraphDeploymentID1)

      const contractRewardsAT1 = updatedSG1.accRewardsPerAllocatedToken
      expect(expectedRewardsAT1).eq(contractRewardsAT1)
    })
  })

  describe('getRewards', function () {
    it('calcuate rewards using the subgraph signalled + allocated tokens', async function () {
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
          channelPubKey,
          assetHolder.address,
          toGRT('0.1'),
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

      const expectedRewards = contractRewardsAT1.mul(tokensToAllocate).div(constants.WeiPerEther)
      expect(expectedRewards).eq(contractRewards)
    })
  })

  describe('assign rewards and claim', function () {
    it('should distribute rewards when allocation settled and be able to claim them', async function () {
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
          channelPubKey,
          assetHolder.address,
          toGRT('0.1'),
        )

      // Jump
      await advanceToNextEpoch(epochManager)

      // Settle allocation. At this point rewards should be collected for that indexer
      await staking.connect(indexer1.signer).settle(allocationID, randomHexBytes())

      // Check that rewards are put into indexer claimable pool
      const expectedIndexer1Rewards = toGRT('15844017.4932529092259875') // calculated manually based on signalled tokens, allocated and time
      const contractIndexer1Rewards = await rewardsManager.indexerRewards(indexer1.address)
      expect(expectedIndexer1Rewards).eq(contractIndexer1Rewards)

      // Try to claim those rewards from wrong indexer should fail
      const tx1 = rewardsManager.connect(indexer2.signer).claim(false)
      await expect(tx1).revertedWith('No rewards available for claiming')

      // Try to claim those rewards and get funds back to indexer
      const beforeIndexerBalance = await grt.balanceOf(indexer1.address)
      const tx2 = rewardsManager.connect(indexer1.signer).claim(false)
      await expect(tx2)
        .emit(rewardsManager, 'RewardsClaimed')
        .withArgs(indexer1.address, expectedIndexer1Rewards)
      const afterIndexerBalance = await grt.balanceOf(indexer1.address)
      expect(afterIndexerBalance).eq(beforeIndexerBalance.add(expectedIndexer1Rewards))
    })
  })
})

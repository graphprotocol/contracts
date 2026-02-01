import { Curation } from '@graphprotocol/contracts'
import { EpochManager } from '@graphprotocol/contracts'
import { GraphToken } from '@graphprotocol/contracts'
import { IStaking } from '@graphprotocol/contracts'
import { RewardsManager } from '@graphprotocol/contracts'
import {
  deriveChannelKey,
  formatGRT,
  GraphNetworkContracts,
  helpers,
  randomHexBytes,
  toBN,
  toGRT,
} from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber as BN } from 'bignumber.js'
import { expect } from 'chai'
import { BigNumber, constants } from 'ethers'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

const { HashZero, WeiPerEther } = constants

const toRound = (n: BigNumber) => formatGRT(n.add(toGRT('0.5'))).split('.')[0]

describe('Rewards - Calculations', () => {
  const graph = hre.graph()
  let governor: SignerWithAddress
  let curator1: SignerWithAddress
  let curator2: SignerWithAddress
  let indexer1: SignerWithAddress
  let indexer2: SignerWithAddress
  let assetHolder: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let grt: GraphToken
  let curation: Curation
  let epochManager: EpochManager
  let staking: IStaking
  let rewardsManager: RewardsManager

  // Derive some channel keys for each indexer used to sign attestations
  const channelKey1 = deriveChannelKey()

  const subgraphDeploymentID1 = randomHexBytes()
  const subgraphDeploymentID2 = randomHexBytes()

  const allocationID1 = channelKey1.address

  const metadata = HashZero

  const ISSUANCE_RATE_PERIODS = 4 // blocks required to issue 800 GRT rewards
  const ISSUANCE_PER_BLOCK = toBN('200000000000000000000') // 200 GRT every block

  // Core formula that gets accumulated rewards per signal for a period of time
  const getRewardsPerSignal = (k: BN, t: BN, s: BN): string => {
    if (s.eq(0)) {
      return '0'
    }
    return k.times(t).div(s).toPrecision(18).toString()
  }

  // Tracks the accumulated rewards as totalSignalled or supply changes across snapshots
  class RewardsTracker {
    totalSignalled = BigNumber.from(0)
    lastUpdatedBlock = 0
    accumulated = BigNumber.from(0)

    static async create() {
      const tracker = new RewardsTracker()
      await tracker.snapshot()
      return tracker
    }

    async snapshot() {
      this.accumulated = this.accumulated.add(await this.accrued())
      this.totalSignalled = await grt.balanceOf(curation.address)
      this.lastUpdatedBlock = await helpers.latestBlock()
      return this
    }

    async elapsedBlocks() {
      const currentBlock = await helpers.latestBlock()
      return currentBlock - this.lastUpdatedBlock
    }

    async accrued() {
      const nBlocks = await this.elapsedBlocks()
      return this.accruedByElapsed(nBlocks)
    }

    accruedByElapsed(nBlocks: BigNumber | number) {
      const n = getRewardsPerSignal(
        new BN(ISSUANCE_PER_BLOCK.toString()),
        new BN(nBlocks.toString()),
        new BN(this.totalSignalled.toString()),
      )
      return toGRT(n)
    }
  }

  // Test accumulated rewards per signal
  const shouldGetNewRewardsPerSignal = async (nBlocks = ISSUANCE_RATE_PERIODS) => {
    // -- t0 --
    const tracker = await RewardsTracker.create()

    // Jump
    await helpers.mine(nBlocks)

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
    const testAccounts = await graph.getTestAccounts()
    ;[indexer1, indexer2, curator1, curator2, assetHolder] = testAccounts
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

  context('issuing rewards', function () {
    beforeEach(async function () {
      // 5% minute rate (4 blocks)
      await rewardsManager.connect(governor).setIssuancePerBlock(ISSUANCE_PER_BLOCK)
    })

    describe('getNewRewardsPerSignal', function () {
      it('accrued per signal when no tokens signalled', async function () {
        // When there is no tokens signalled no rewards are accrued
        await helpers.mineEpoch(epochManager)
        const accrued = await rewardsManager.getNewRewardsPerSignal()
        expect(accrued).eq(0)
      })

      it('accrued per signal when tokens signalled', async function () {
        // Update total signalled
        const tokensToSignal = toGRT('1000')
        await curation.connect(curator1).mint(subgraphDeploymentID1, tokensToSignal, 0)

        // Check
        await shouldGetNewRewardsPerSignal()
      })

      it('accrued per signal when signalled tokens w/ many subgraphs', async function () {
        // Update total signalled
        await curation.connect(curator1).mint(subgraphDeploymentID1, toGRT('1000'), 0)

        // Check
        await shouldGetNewRewardsPerSignal()

        // Update total signalled
        await curation.connect(curator2).mint(subgraphDeploymentID2, toGRT('250'), 0)

        // Check
        await shouldGetNewRewardsPerSignal()
      })
    })

    describe('updateAccRewardsPerSignal', function () {
      it('update the accumulated rewards per signal state', async function () {
        // Update total signalled
        await curation.connect(curator1).mint(subgraphDeploymentID1, toGRT('1000'), 0)
        // Snapshot
        const tracker = await RewardsTracker.create()

        // Update
        await rewardsManager.connect(governor).updateAccRewardsPerSignal()
        const contractAccrued = await rewardsManager.accRewardsPerSignal()

        // Check
        const expectedAccrued = await tracker.accrued()
        expect(toRound(expectedAccrued)).eq(toRound(contractAccrued))
      })

      it('update the accumulated rewards per signal state after many blocks', async function () {
        // Update total signalled
        await curation.connect(curator1).mint(subgraphDeploymentID1, toGRT('1000'), 0)
        // Snapshot
        const tracker = await RewardsTracker.create()

        // Jump
        await helpers.mine(ISSUANCE_RATE_PERIODS)

        // Update
        await rewardsManager.connect(governor).updateAccRewardsPerSignal()
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
        await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)
        const tracker1 = await RewardsTracker.create()

        // Curator2 - Update total signalled
        const signalled2 = toGRT('500')
        await curation.connect(curator2).mint(subgraphDeploymentID2, signalled2, 0)

        // Snapshot
        const tracker2 = await RewardsTracker.create()
        await tracker1.snapshot()

        // Jump
        await helpers.mine(ISSUANCE_RATE_PERIODS)

        // Snapshot
        await tracker1.snapshot()
        await tracker2.snapshot()

        // Calculate rewards
        const rewardsPerSignal1 = tracker1.accumulated
        const rewardsPerSignal2 = tracker2.accumulated
        const expectedRewardsSG1 = rewardsPerSignal1.mul(signalled1).div(WeiPerEther)
        const expectedRewardsSG2 = rewardsPerSignal2.mul(signalled2).div(WeiPerEther)

        // Get rewards from contract
        const contractRewardsSG1 = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID1)
        const contractRewardsSG2 = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID2)

        // Check
        expect(toRound(expectedRewardsSG1)).eq(toRound(contractRewardsSG1))
        expect(toRound(expectedRewardsSG2)).eq(toRound(contractRewardsSG2))
      })

      it('should return zero rewards when subgraph signal is below minimum threshold', async function () {
        // Set a high minimum signal threshold
        const highMinimumSignal = toGRT('2000')
        await rewardsManager.connect(governor).setMinimumSubgraphSignal(highMinimumSignal)

        // Signal less than the minimum threshold
        const lowSignal = toGRT('1000')
        await curation.connect(curator1).mint(subgraphDeploymentID1, lowSignal, 0)

        // Jump some blocks to potentially accrue rewards
        await helpers.mine(ISSUANCE_RATE_PERIODS)

        // Check that no rewards are accrued due to minimum signal threshold
        const contractRewards = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID1)
        expect(contractRewards).eq(0)
      })
    })

    describe('onSubgraphSignalUpdate', function () {
      it('update the accumulated rewards for subgraph state', async function () {
        // Update total signalled
        const signalled1 = toGRT('1500')
        await curation.connect(curator1).mint(subgraphDeploymentID1, signalled1, 0)
        // Snapshot
        const tracker1 = await RewardsTracker.create()

        // Jump
        await helpers.mine(ISSUANCE_RATE_PERIODS)

        // Update
        await rewardsManager.connect(governor).onSubgraphSignalUpdate(subgraphDeploymentID1)

        // Check
        const contractRewardsSG1 = (await rewardsManager.subgraphs(subgraphDeploymentID1)).accRewardsForSubgraph
        const rewardsPerSignal1 = await tracker1.accrued()
        const expectedRewardsSG1 = rewardsPerSignal1.mul(signalled1).div(WeiPerEther)
        expect(toRound(expectedRewardsSG1)).eq(toRound(contractRewardsSG1))

        const contractAccrued = await rewardsManager.accRewardsPerSignal()
        const expectedAccrued = await tracker1.accrued()
        expect(toRound(expectedAccrued)).eq(toRound(contractAccrued))

        const contractBlockUpdated = await rewardsManager.accRewardsPerSignalLastBlockUpdated()
        const expectedBlockUpdated = await helpers.latestBlock()
        expect(expectedBlockUpdated).eq(contractBlockUpdated)
      })
    })

    describe('getAccRewardsPerAllocatedToken', function () {
      it('accrued per allocated token', async function () {
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

        // Jump
        await helpers.mine(ISSUANCE_RATE_PERIODS)

        // Check
        const sg1 = await rewardsManager.subgraphs(subgraphDeploymentID1)
        // We trust this function because it was individually tested in previous test
        const accRewardsForSubgraphSG1 = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID1)
        const accruedRewardsSG1 = accRewardsForSubgraphSG1.sub(sg1.accRewardsForSubgraphSnapshot)
        const expectedRewardsAT1 = accruedRewardsSG1.mul(WeiPerEther).div(tokensToAllocate)
        const contractRewardsAT1 = (await rewardsManager.getAccRewardsPerAllocatedToken(subgraphDeploymentID1))[0]
        expect(expectedRewardsAT1).eq(contractRewardsAT1)
      })
    })

    describe('onSubgraphAllocationUpdate', function () {
      it('update the accumulated rewards for allocated tokens state', async function () {
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

        // Jump
        await helpers.mine(ISSUANCE_RATE_PERIODS)

        // Prepare expected results
        // Note: rewards from signal to allocation (2 blocks) are reclaimed since no allocations exist yet
        const expectedSubgraphRewards = toGRT('1000') // 5 blocks since allocation to when we do getAccRewardsForSubgraph
        const expectedRewardsAT = toGRT('0.08') // allocated during 5 blocks: 1000 GRT, divided by 12500 allocated tokens

        // Update
        await rewardsManager.connect(governor).onSubgraphAllocationUpdate(subgraphDeploymentID1)

        // Check on demand results saved
        const subgraph = await rewardsManager.subgraphs(subgraphDeploymentID1)
        const contractSubgraphRewards = await rewardsManager.getAccRewardsForSubgraph(subgraphDeploymentID1)
        const contractRewardsAT = subgraph.accRewardsPerAllocatedToken

        expect(toRound(expectedSubgraphRewards)).eq(toRound(contractSubgraphRewards))
        expect(toRound(expectedRewardsAT.mul(1000))).eq(toRound(contractRewardsAT.mul(1000)))
      })
    })
  })
})

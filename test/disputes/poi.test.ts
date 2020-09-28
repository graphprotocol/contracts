import { expect } from 'chai'
import { utils } from 'ethers'

import { DisputeManager } from '../../build/typechain/contracts/DisputeManager'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'
import {
  advanceToNextEpoch,
  deriveChannelKey,
  getAccounts,
  randomHexBytes,
  toBN,
  toGRT,
  Account,
} from '../lib/testHelpers'

const { keccak256 } = utils

describe('DisputeManager:POI', async () => {
  let other: Account
  let governor: Account
  let arbitrator: Account
  let indexer: Account
  let fisherman: Account
  let assetHolder: Account

  let fixture: NetworkFixture

  let disputeManager: DisputeManager
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

  // Derive some channel keys for each indexer used to sign attestations
  const indexerChannelKey = deriveChannelKey()

  // Test values
  const fishermanTokens = toGRT('100000')
  const fishermanDeposit = toGRT('1000')
  const indexerTokens = toGRT('100000')
  const indexerAllocatedTokens = toGRT('10000')
  const allocationID = indexerChannelKey.address
  const subgraphDeploymentID = randomHexBytes(32)
  const metadata = randomHexBytes(32)
  const poi = randomHexBytes(32) // proof of indexing

  async function setupIndexers() {
    // Dispute manager is allowed to slash
    await staking.connect(governor.signer).setSlasher(disputeManager.address, true)

    // Stake & allocate
    const indexerList = [{ wallet: indexer, allocationID: indexerChannelKey.address }]
    for (const activeIndexer of indexerList) {
      const indexerWallet = activeIndexer.wallet
      const indexerAllocationID = activeIndexer.allocationID

      // Give some funds to the indexer
      await grt.connect(governor.signer).mint(indexerWallet.address, indexerTokens)
      await grt.connect(indexerWallet.signer).approve(staking.address, indexerTokens)

      // Indexer stake funds
      await staking.connect(indexerWallet.signer).stake(indexerTokens)
      await staking
        .connect(indexerWallet.signer)
        .allocate(subgraphDeploymentID, indexerAllocatedTokens, indexerAllocationID, metadata)
    }
  }

  before(async function () {
    ;[other, governor, arbitrator, indexer, fisherman, assetHolder] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ disputeManager, epochManager, grt, staking } = await fixture.load(
      governor.signer,
      other.signer,
      arbitrator.signer,
    ))

    // Give some funds to the fisherman
    await grt.connect(governor.signer).mint(fisherman.address, fishermanTokens)
    await grt.connect(fisherman.signer).approve(disputeManager.address, fishermanTokens)

    // Allow the asset holder
    await staking.connect(governor.signer).setAssetHolder(assetHolder.address, true)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('disputes', function () {
    it('reject create a dispute if allocation does not exist', async function () {
      const invalidAllocationID = randomHexBytes(20)

      // Create dispute
      const tx = disputeManager
        .connect(fisherman.signer)
        .createIndexingDispute(invalidAllocationID, fishermanDeposit)
      await expect(tx).revertedWith('Dispute allocation must exist')
    })

    it('reject create a dispute if indexer below stake', async function () {
      // This tests reproduce the case when someones present a dispute for
      // an indexer that is under the minimum required staked amount

      const indexerCollectedTokens = toGRT('10')

      // Give some funds to the indexer
      await grt.connect(governor.signer).mint(indexer.address, indexerTokens)
      await grt.connect(indexer.signer).approve(staking.address, indexerTokens)

      // Give some funds to the channel
      await grt.connect(governor.signer).mint(assetHolder.address, indexerCollectedTokens)
      await grt.connect(assetHolder.signer).approve(staking.address, indexerCollectedTokens)

      // Set the thawing period to zero to make the test easier
      await staking.connect(governor.signer).setThawingPeriod(toBN('0'))

      // Indexer stake funds, allocate, close, unstake and withdraw the stake fully
      await staking.connect(indexer.signer).stake(indexerTokens)
      const tx1 = await staking
        .connect(indexer.signer)
        .allocate(subgraphDeploymentID, indexerAllocatedTokens, allocationID, metadata)
      const receipt1 = await tx1.wait()
      const event1 = staking.interface.parseLog(receipt1.logs[0]).args
      await advanceToNextEpoch(epochManager) // wait the required one epoch to close allocation
      await staking.connect(assetHolder.signer).collect(indexerCollectedTokens, event1.allocationID)
      await staking.connect(indexer.signer).closeAllocation(event1.allocationID, poi)
      await staking.connect(indexer.signer).unstake(indexerTokens)
      await staking.connect(indexer.signer).withdraw() // no thawing period so we are good

      // Create dispute
      const tx = disputeManager
        .connect(fisherman.signer)
        .createIndexingDispute(event1.allocationID, fishermanDeposit)
      await expect(tx).revertedWith('Dispute under minimum indexer stake amount')
    })

    context('> when indexer is staked', function () {
      beforeEach(async function () {
        await setupIndexers()
      })

      it('should create a dispute', async function () {
        // Create dispute
        const tx = disputeManager
          .connect(fisherman.signer)
          .createIndexingDispute(allocationID, fishermanDeposit)
        await expect(tx)
          .emit(disputeManager, 'IndexingDisputeCreated')
          .withArgs(
            keccak256(allocationID),
            indexer.address,
            fisherman.address,
            fishermanDeposit,
            allocationID,
          )
      })

      context('> when dispute is created', function () {
        beforeEach(async function () {
          // Create dispute
          await disputeManager
            .connect(fisherman.signer)
            .createIndexingDispute(allocationID, fishermanDeposit)
        })

        it('reject create duplicated dispute', async function () {
          const tx = disputeManager
            .connect(fisherman.signer)
            .createIndexingDispute(allocationID, fishermanDeposit)
          await expect(tx).revertedWith('Dispute already created')
        })
      })
    })
  })
})

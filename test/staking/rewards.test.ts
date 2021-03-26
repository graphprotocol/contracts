import { expect } from 'chai'
import { constants, BigNumber } from 'ethers'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'
import {
  advanceBlocks,
  advanceToNextEpoch,
  deriveChannelKey,
  getAccounts,
  randomAddress,
  randomHexBytes,
  weightedAverage,
  toGRT,
  Account,
  latestBlock,
  toBN,
} from '../lib/testHelpers'

const { AddressZero, HashZero } = constants

describe('Staking::Rewards', () => {
  let governor: Account
  let indexer: Account
  let curator: Account

  let fixture: NetworkFixture

  let curation: Curation
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: Staking

  // Test values
  const indexerTokens = toGRT('100000')
  const curatorTokens = toGRT('100000')

  const allocateThenTimeAndClose = async (
    tokens: BigNumber,
    subgraphDeploymentID: string,
    restake: boolean,
  ) => {
    const metadata = HashZero
    const poi = randomHexBytes(32)
    const channelKey = deriveChannelKey()
    const allocationID = channelKey.address

    await staking
      .connect(indexer.signer)
      .allocate(
        subgraphDeploymentID,
        tokens,
        allocationID,
        metadata,
        await channelKey.generateProof(indexer.address),
      )
    await advanceToNextEpoch(epochManager)
    await advanceToNextEpoch(epochManager)
    await staking.connect(indexer.signer).closeAllocation(allocationID, poi, restake)
  }

  const shouldWithdrawRewards = async () => {
    const beneficiary = randomAddress()

    // Before state
    const beforeRewardsPool = await staking.rewardsPools(indexer.address)
    const beforeStakingBalance = await grt.balanceOf(staking.address)
    const beforeBeneficiaryBalance = await grt.balanceOf(beneficiary)

    // Withdraw rewards
    const tokensToWithdraw = beforeRewardsPool.tokensLocked
    const tx = staking.connect(indexer.signer).withdrawRewards(beneficiary)
    await expect(tx)
      .emit(staking, 'RewardsWithdrawn')
      .withArgs(indexer.address, beneficiary, tokensToWithdraw)

    // After state
    const afterRewardsPool = await staking.rewardsPools(indexer.address)
    const afterStakingBalance = await grt.balanceOf(staking.address)
    const afterBeneficiaryBalance = await grt.balanceOf(beneficiary)

    // Rewards pool updated
    expect(afterRewardsPool.tokensLocked).eq(0)
    expect(afterRewardsPool.tokensLockedUntil).eq(0)

    // Balances updated
    expect(afterStakingBalance).eq(beforeStakingBalance.sub(tokensToWithdraw))
    expect(afterBeneficiaryBalance).eq(beforeBeneficiaryBalance.add(tokensToWithdraw))
  }

  before(async function () {
    ;[governor, indexer, curator] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ grt, staking, epochManager, curation } = await fixture.load(governor.signer))

    // Give some funds to the indexer and approve staking contract to use funds on their behalf
    await grt.connect(governor.signer).mint(indexer.address, indexerTokens)
    await grt.connect(indexer.signer).approve(staking.address, indexerTokens)
    // Give some funds to the curator and approve curation contract to use funds on their behalf
    await grt.connect(governor.signer).mint(curator.address, curatorTokens)
    await grt.connect(curator.signer).approve(curation.address, curatorTokens)

    // Stake from indexer
    await staking.connect(indexer.signer).stake(indexerTokens)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('withdrawRewards', function () {
    const subgraphDeploymentID = randomHexBytes(32)

    it('should withdraw available rewards', async function () {
      // Collect some rewards from allocation
      await curation.connect(curator.signer).mint(subgraphDeploymentID, curatorTokens, 0)
      await allocateThenTimeAndClose(indexerTokens, subgraphDeploymentID, false)

      // Move after lock period
      await advanceBlocks(await staking.thawingPeriod())

      // Withdraw
      await shouldWithdrawRewards()
    })

    it('should update locking period with weighted average on re-deposit', async function () {
      // Set long thawing period
      await staking.setThawingPeriod(200)

      // Collect some rewards from allocation
      await curation.connect(curator.signer).mint(subgraphDeploymentID, curatorTokens, 0)
      await allocateThenTimeAndClose(indexerTokens, subgraphDeploymentID, false)

      // Before state
      const thawingPeriod = await staking.thawingPeriod()
      const beforeRewardsPool = await staking.rewardsPools(indexer.address)

      // Re-deposit on rewards pool
      await allocateThenTimeAndClose(indexerTokens, subgraphDeploymentID, false)

      // After state
      const afterRewardsPool = await staking.rewardsPools(indexer.address)
      const afterBlock = await latestBlock()
      const blockDiff = afterBlock.lt(beforeRewardsPool.tokensLockedUntil)
        ? beforeRewardsPool.tokensLockedUntil.sub(afterBlock)
        : toBN(0)
      const newTokens = afterRewardsPool.tokensLocked.sub(beforeRewardsPool.tokensLocked)
      const newPeriod = await weightedAverage(
        beforeRewardsPool.tokensLocked,
        newTokens,
        blockDiff,
        toBN(thawingPeriod),
      )

      // Token lock period should be averaged
      expect(afterRewardsPool.tokensLocked).gt(beforeRewardsPool.tokensLocked)
      expect(afterRewardsPool.tokensLockedUntil).eq(afterBlock.add(newPeriod))
    })

    it('reject withdraw if no tokens available', async function () {
      const tx = staking.connect(indexer.signer).withdrawRewards(indexer.address)
      await expect(tx).revertedWith('rewards-empty')
    })

    it('reject withdraw if empty beneficiary', async function () {
      // Collect some rewards from allocation
      await curation.connect(curator.signer).mint(subgraphDeploymentID, curatorTokens, 0)
      await allocateThenTimeAndClose(indexerTokens, subgraphDeploymentID, false)

      // Move after lock period
      await advanceBlocks(await staking.thawingPeriod())

      const tx = staking.connect(indexer.signer).withdrawRewards(AddressZero)
      await expect(tx).revertedWith('!rewards-beneficiary')
    })

    it('reject withdraw if under lock period', async function () {
      // Collect some rewards from allocation
      await curation.connect(curator.signer).mint(subgraphDeploymentID, curatorTokens, 0)
      await allocateThenTimeAndClose(indexerTokens, subgraphDeploymentID, false)

      const tx = staking.connect(indexer.signer).withdrawRewards(indexer.address)
      await expect(tx).revertedWith('rewards-locked')
    })
  })
})

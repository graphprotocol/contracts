import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'
import { keccak256 } from 'ethers'
import { toUtf8Bytes } from 'ethers'

import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { IHorizonStaking, IRewardsManager } from '../../../typechain-types'

import { indexers } from '../../../scripts/e2e/fixtures/indexers'

describe('Operator', () => {
  let horizonStaking: IHorizonStaking
  let rewardsManager: IRewardsManager
  let snapshotId: string

  // TODO: FIX THIS
  const subgraphServiceAddress = '0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B'

  before(() => {
    const graph = hre.graph()

    // Get contracts
    horizonStaking = graph.horizon!.contracts.HorizonStaking as unknown as IHorizonStaking
    rewardsManager = graph.horizon!.contracts.RewardsManager as unknown as IRewardsManager
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Existing Protocol Users', () => {
    let indexer: SignerWithAddress
    let operator: SignerWithAddress
    let allocationID: string
    let allocationTokens: bigint
    let delegationIndexingCut: number

    before(async () => {
      const indexerFixture = indexers[0]
      const allocationFixture = indexerFixture.allocations[0]

      // Get signers
      indexer = await ethers.getSigner(indexerFixture.address)
      operator = (await ethers.getSigners())[0]

      // Get allocation details
      allocationID = allocationFixture.allocationID
      allocationTokens = allocationFixture.tokens
      delegationIndexingCut = indexerFixture.indexingRewardCut

      // Set the operator
      await horizonStaking.connect(indexer).setOperator(subgraphServiceAddress, operator.address, true)
    })

    it('should allow the operator to close an open legacy allocation and collect rewards', async () => {
      // Use a non-zero POI
      const poi = ethers.getBytes(keccak256(toUtf8Bytes('poi')))
      const thawingPeriod = await horizonStaking.__DEPRECATED_getThawingPeriod()

      // Get delegation pool before closing allocation
      const delegationPoolBefore = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
      const delegationPoolTokensBefore = delegationPoolBefore.tokens

      // Mine blocks to simulate time passing
      const halfThawingPeriod = Number(thawingPeriod) / 2
      for (let i = 0; i < halfThawingPeriod; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Get idle stake before closing allocation
      const idleStakeBefore = await horizonStaking.getIdleStake(indexer.address)

      // Close allocation
      await horizonStaking.connect(operator).closeAllocation(allocationID, poi)

      // Get rewards
      const rewards = await rewardsManager.getRewards(horizonStaking.target, allocationID)
      // Verify rewards are not zero
      expect(rewards).to.not.equal(0, 'Rewards were not transferred to service provider')

      // Verify rewards minus delegation cut are restaked
      const idleStakeAfter = await horizonStaking.getIdleStake(indexer.address)
      const idleStakeRewardsTokens = rewards * BigInt(delegationIndexingCut) / 1000000n
      expect(idleStakeAfter).to.equal(idleStakeBefore + allocationTokens + idleStakeRewardsTokens, 'Rewards were not restaked')

      // Verify delegators cut is added to delegation pool
      const delegationPool = await horizonStaking.getDelegationPool(indexer.address, subgraphServiceAddress)
      const delegationPoolTokensAfter = delegationPool.tokens
      const delegationRewardsTokens = rewards - idleStakeRewardsTokens
      expect(delegationPoolTokensAfter).to.equal(delegationPoolTokensBefore + delegationRewardsTokens, 'Delegators cut was not added to delegation pool')
    })
  })
})

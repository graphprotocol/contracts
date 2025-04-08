import hre from 'hardhat'

import { createPOIFromString } from '@graphprotocol/toolshed/utils'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { indexers } from '../../../tasks/test/fixtures/indexers'

import type { HorizonStaking, HorizonStakingExtension, RewardsManager } from '@graphprotocol/toolshed/deployments/horizon'

describe('Operator', () => {
  let horizonStaking: HorizonStaking
  let rewardsManager: RewardsManager
  let snapshotId: string

  // Subgraph service address is not set for integration tests
  const subgraphServiceAddress = '0x0000000000000000000000000000000000000000'

  before(() => {
    const graph = hre.graph()

    // Get contracts
    horizonStaking = graph.horizon!.contracts.HorizonStaking
    rewardsManager = graph.horizon!.contracts.RewardsManager
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
    let indexer: HardhatEthersSigner
    let operator: HardhatEthersSigner
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
      const poi = createPOIFromString('poi')
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
      await (horizonStaking as HorizonStakingExtension).connect(operator).closeAllocation(allocationID, poi)

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

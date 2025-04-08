import hre from 'hardhat'

import { ethers } from 'hardhat'
import { expect } from 'chai'

import { createPOIFromString } from '@graphprotocol/toolshed'
import { indexers } from '../../../tasks/test/fixtures/indexers'

import type { EpochManager, HorizonStaking, HorizonStakingExtension } from '@graphprotocol/toolshed/deployments/horizon'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Permissionless', () => {
  let horizonStaking: HorizonStaking
  let epochManager: EpochManager
  let snapshotId: string

  before(() => {
    const graph = hre.graph()

    // Get contracts
    horizonStaking = graph.horizon!.contracts.HorizonStaking
    epochManager = graph.horizon!.contracts.EpochManager
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('After max allocation epochs', () => {
    let indexer: HardhatEthersSigner
    let anySigner: HardhatEthersSigner
    let allocationID: string
    let allocationTokens: bigint

    before(async () => {
      // Get signers
      indexer = await ethers.getSigner(indexers[0].address)
      anySigner = (await ethers.getSigners())[19]

      // Get allocation details
      allocationID = indexers[0].allocations[0].allocationID
      allocationTokens = indexers[0].allocations[0].tokens
    })

    it('should allow any user to close an allocation with zero POI after 28 epochs', async () => {
      // Get indexer's idle stake before closing allocation
      const idleStakeBefore = await horizonStaking.getIdleStake(indexer.address)

      // Mine blocks to simulate 28 epochs passing
      const startingEpoch = await epochManager.currentEpoch()
      while (await epochManager.currentEpoch() - startingEpoch < 28) {
        await ethers.provider.send('evm_mine', [])
      }

      // Close allocation
      const poi = createPOIFromString('poi')
      await (horizonStaking as HorizonStakingExtension).connect(anySigner).closeAllocation(allocationID, poi)

      // Get indexer's idle stake after closing allocation
      const idleStakeAfter = await horizonStaking.getIdleStake(indexer.address)

      // Verify allocation tokens were added to indexer's idle stake but no rewards were collected
      expect(idleStakeAfter).to.be.equal(idleStakeBefore + allocationTokens)
    })
  })
})

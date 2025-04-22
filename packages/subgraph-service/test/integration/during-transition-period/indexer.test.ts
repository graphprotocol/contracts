import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

import { indexers } from '../../../tasks/test/fixtures/indexers'
import { ISubgraphService } from '../../../typechain-types'
import { encodeStartServiceData } from '@graphprotocol/toolshed'

describe('Indexer', () => {
  let subgraphService: ISubgraphService
  let snapshotId: string

  // Test addresses
  let governor: HardhatEthersSigner
  let indexer: HardhatEthersSigner
  let allocationId: string
  let subgraphDeploymentId: string
  let allocationPrivateKey: string

  const graph = hre.graph()
  const { generateAllocationProof } = graph.subgraphService.actions

  before(async () => {
    // Get contracts
    subgraphService = graph.subgraphService.contracts.SubgraphService

    // Get governor and non-owner
    governor = await graph.accounts.getGovernor()
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Allocation', () => {
    beforeEach(async () => {
      // Get indexer
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)

      // Generate test addresses
      const allocation = indexerFixture.legacyAllocations[0]
      allocationId = allocation.allocationID
      subgraphDeploymentId = allocation.subgraphDeploymentID
      allocationPrivateKey = allocation.allocationPrivateKey
    })

    it('should not be able to create an allocation with an AllocationID that already exists in HorizonStaking contract', async () => {
      // Build allocation proof
      const signature = await generateAllocationProof(allocationPrivateKey, [indexer.address, allocationId])

      // Attempt to create an allocation with the same ID
      const data = encodeStartServiceData(subgraphDeploymentId, 1000n, allocationId, signature)

      await expect(
        subgraphService.connect(indexer).startService(
          indexer.address,
          data,
        ),
      ).to.be.revertedWithCustomError(
        subgraphService,
        'LegacyAllocationAlreadyExists',
      ).withArgs(allocationId)
    })

    it('should not be able to create an allocation that was already migrated by the owner', async () => {
      // Migrate legacy allocation
      await subgraphService.connect(governor).migrateLegacyAllocation(
        indexer.address,
        allocationId,
        subgraphDeploymentId,
      )

      // Build allocation proof
      const signature = await generateAllocationProof(allocationPrivateKey, [indexer.address, allocationId])

      // Attempt to create the same allocation
      const data = encodeStartServiceData(subgraphDeploymentId, 1000n, allocationId, signature)

      await expect(
        subgraphService.connect(indexer).startService(
          indexer.address,
          data,
        ),
      ).to.be.revertedWithCustomError(
        subgraphService,
        'LegacyAllocationAlreadyExists',
      ).withArgs(allocationId)
    })
  })
})

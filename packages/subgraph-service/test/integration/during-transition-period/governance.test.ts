import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

import { ISubgraphService } from '../../../typechain-types'

describe('Governance', () => {
  let subgraphService: ISubgraphService
  let snapshotId: string

  // Test addresses
  let governor: HardhatEthersSigner
  let indexer: HardhatEthersSigner
  let nonOwner: HardhatEthersSigner
  let allocationId: string
  let subgraphDeploymentId: string

  const graph = hre.graph()

  before(() => {
    subgraphService = graph.subgraphService.contracts.SubgraphService
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])

    // Get signers
    governor = await graph.accounts.getGovernor()
    ;[indexer, nonOwner] = await graph.accounts.getTestAccounts()

    // Generate test addresses
    allocationId = ethers.Wallet.createRandom().address
    subgraphDeploymentId = ethers.keccak256(ethers.toUtf8Bytes('test-subgraph-deployment'))
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Legacy Allocation Migration', () => {
    it('should migrate legacy allocation', async () => {
      // Migrate legacy allocation
      await subgraphService.connect(governor).migrateLegacyAllocation(
        indexer.address,
        allocationId,
        subgraphDeploymentId,
      )

      // Verify the legacy allocation was migrated
      const legacyAllocation = await subgraphService.getLegacyAllocation(allocationId)
      expect(legacyAllocation.indexer).to.equal(indexer.address)
      expect(legacyAllocation.subgraphDeploymentId).to.equal(subgraphDeploymentId)
    })

    it('should not allow non-owner to migrate legacy allocation', async () => {
      // Attempt to migrate legacy allocation as non-owner
      await expect(
        subgraphService.connect(nonOwner).migrateLegacyAllocation(
          indexer.address,
          allocationId,
          subgraphDeploymentId,
        ),
      ).to.be.revertedWithCustomError(
        subgraphService,
        'OwnableUnauthorizedAccount',
      )
    })

    it('should not allow migrating a legacy allocation that was already migrated', async () => {
      // First migration
      await subgraphService.connect(governor).migrateLegacyAllocation(
        indexer.address,
        allocationId,
        subgraphDeploymentId,
      )

      // Attempt to migrate the same allocation again
      await expect(
        subgraphService.connect(governor).migrateLegacyAllocation(
          indexer.address,
          allocationId,
          subgraphDeploymentId,
        ),
      ).to.be.revertedWithCustomError(
        subgraphService,
        'LegacyAllocationAlreadyExists',
      ).withArgs(allocationId)
    })
  })
})

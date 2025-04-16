import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { SubgraphService } from '../../../../typechain-types'

import { indexers } from '../../../../tasks/test/fixtures/indexers'

describe('Permissionless', () => {
  let subgraphService: SubgraphService
  let snapshotId: string

  // Test data
  let indexer: SignerWithAddress
  let anyone: SignerWithAddress
  let allocationId: string
  let subgraphDeploymentId: string
  let allocationTokens: bigint

  const graph = hre.graph()
  const { generateAllocationProof } = graph.subgraphService.actions

  before(async () => {
    // Get contracts
    subgraphService = graph.subgraphService.contracts.SubgraphService as unknown as SubgraphService

    // Get anyone address
    ;[anyone] = await graph.accounts.getTestAccounts()
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Non-altruistic allocation', () => {
    beforeEach(async () => {
      // Get indexer
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)

      // Get allocation
      const allocation = indexerFixture.allocations[0]
      allocationId = allocation.allocationID
      subgraphDeploymentId = allocation.subgraphDeploymentID
      allocationTokens = allocation.tokens
    })

    it('should allow anyone to close an allocation after max POI staleness passes', async () => {
      // Wait for POI staleness
      const maxPOIStaleness = await subgraphService.maxPOIStaleness()
      await ethers.provider.send('evm_increaseTime', [Number(maxPOIStaleness) + 1])
      await ethers.provider.send('evm_mine', [])

      // Get before state
      const beforeLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)

      // Close allocation as anyone
      await subgraphService.connect(anyone).closeStaleAllocation(allocationId)

      // Verify allocation is closed
      const afterAllocation = await subgraphService.getAllocation(allocationId)
      expect(afterAllocation.closedAt).to.not.equal(0, 'Allocation should be closed')

      // Verify tokens are released
      const afterLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)
      expect(afterLockedTokens).to.equal(beforeLockedTokens - allocationTokens, 'Tokens should be released')
    })
  })

  describe('Altruistic allocation', () => {
    let allocationPrivateKey: string

    beforeEach(async () => {
      // Get indexer
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)

      // Generate random allocation
      const wallet = ethers.Wallet.createRandom()
      allocationId = wallet.address
      allocationPrivateKey = wallet.privateKey
      subgraphDeploymentId = indexerFixture.allocations[0].subgraphDeploymentID
      allocationTokens = 0n

      // Start allocation
      const signature = await generateAllocationProof(allocationPrivateKey, [indexer.address, allocationId])
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes32', 'uint256', 'address', 'bytes'],
        [subgraphDeploymentId, allocationTokens, allocationId, signature],
      )
      await subgraphService.connect(indexer).startService(indexer.address, data)
    })

    it('should not allow closing an altruistic allocation permissionless', async () => {
      // Wait for POI staleness
      const maxPOIStaleness = await subgraphService.maxPOIStaleness()
      await ethers.provider.send('evm_increaseTime', [Number(maxPOIStaleness) + 1])
      await ethers.provider.send('evm_mine', [])

      // Attempt to close allocation as anyone
      await expect(
        subgraphService.connect(anyone).closeStaleAllocation(allocationId),
      ).to.be.revertedWithCustomError(
        subgraphService,
        'SubgraphServiceAllocationIsAltruistic',
      ).withArgs(allocationId)
    })
  })
})

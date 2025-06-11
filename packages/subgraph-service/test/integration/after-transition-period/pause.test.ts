import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import { ethers } from 'hardhat'

describe('Pausing', () => {
  let snapshotId: string

  // Test addresses
  let pauseGuardian: HardhatEthersSigner
  let governor: HardhatEthersSigner
  const graph = hre.graph()
  const subgraphService = graph.subgraphService.contracts.SubgraphService

  before(async () => {
    pauseGuardian = await graph.accounts.getPauseGuardian()
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

  describe('SubgraphService', () => {
    it('should be pausable by pause guardian', async () => {
      await subgraphService.connect(pauseGuardian).pause()
      expect(await subgraphService.paused()).to.equal(true)
    })

    it('should be pausable by governor', async () => {
      await subgraphService.connect(governor).pause()
      expect(await subgraphService.paused()).to.equal(true)
    })
  })
})

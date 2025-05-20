import hre from 'hardhat'

import { ethers } from 'hardhat'
import { expect } from 'chai'

import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Pausing', () => {
  let snapshotId: string

  // Test addresses
  let pauseGuardian: HardhatEthersSigner
  let governor: HardhatEthersSigner

  const graph = hre.graph()
  const controller = graph.horizon.contracts.Controller

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

  describe('HorizonStaking', () => {
    it('should be pauseable by pause guardian', async () => {
      await controller.connect(pauseGuardian).setPaused(true)
      expect(await controller.paused()).to.equal(true)
    })

    it('should be pauseable by governor', async () => {
      await controller.connect(governor).setPaused(true)
      expect(await controller.paused()).to.equal(true)
    })
  })
})

import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { Contract, ethers } from 'ethers'
import hre from 'hardhat'

import removedABI from './abis/staking'
import allocations from './fixtures/allocations'
import indexers from './fixtures/indexers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { helpers, randomHexBytes } from '@graphprotocol/sdk'

chai.use(chaiAsPromised)

describe('[BEFORE UPGRADE] Exponential rebates upgrade', () => {
  const graph = hre.graph()
  const { Staking, EpochManager } = graph.contracts

  const deployedStaking = new Contract(
    Staking.address,
    new ethers.utils.Interface([...Staking.interface.format(), ...removedABI]),
    graph.provider,
  )

  describe('> Storage variables', () => {
    it(`channelDisputeEpochs should exist`, async function () {
      await expect(deployedStaking.channelDisputeEpochs()).to.eventually.be.fulfilled
    })
    it(`rebates should exist`, async function () {
      await expect(deployedStaking.rebates(123)).to.eventually.be.fulfilled
    })
  })

  describe('> Allocation state transitions', () => {
    it('should validate fixture data on forked chain', async function () {
      for (const allocation of allocations) {
        await expect(Staking.getAllocationState(allocation.id)).to.eventually.equal(
          allocation.state,
        )
      }
    })
  })

  describe('> Indexer actions', () => {
    before(async function () {
      // Impersonate indexers
      for (const indexer of indexers) {
        await helpers.impersonateAccount(indexer.address)
        await helpers.setBalance(indexer.address, 100)
        indexer.signer = await SignerWithAddress.create(graph.provider.getSigner(indexer.address))
      }
    })

    it('should be able to collect and claim rebates', async function () {
      for (const indexer of indexers) {
        for (const allocation of indexer.allocationsBatch1) {
          // Close allocation first
          await helpers.mineEpoch(EpochManager)
          await Staking.connect(indexer.signer).closeAllocation(allocation.id, randomHexBytes())

          // Collect query fees
          const assetHolder = await graph.getDeployer()
          await expect(
            Staking.connect(assetHolder).collect(ethers.utils.parseEther('1000'), allocation.id),
          ).to.eventually.be.fulfilled

          // Claim rebate
          await helpers.mineEpoch(EpochManager, 7)
          const tx = deployedStaking.connect(indexer.signer).claim(allocation.id, false)
          await expect(tx).to.eventually.be.fulfilled
          await expect(tx).to.emit(deployedStaking, 'RebateClaimed')
        }
      }
    })
  })
})

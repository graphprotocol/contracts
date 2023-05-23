import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { Contract } from 'ethers'
import hre from 'hardhat'

import removedABI from './abis/staking'
import allocations from './fixtures/allocations'

chai.use(chaiAsPromised)

describe('[BEFORE UPGRADE] Exponential rebates upgrade', () => {
  const graph = hre.graph()
  const { Staking } = graph.contracts
  const deployedStaking = new Contract(Staking.address, removedABI, graph.provider)

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
})

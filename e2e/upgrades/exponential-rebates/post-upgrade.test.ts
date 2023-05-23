import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { Contract } from 'ethers'
import hre from 'hardhat'

import removedABI from './abis/staking'
import allocations, { AllocationState } from './fixtures/allocations'

chai.use(chaiAsPromised)

describe('[AFTER UPGRADE] Exponential rebates upgrade', () => {
  const graph = hre.graph()
  const { Staking } = graph.contracts
  const deployedStaking = new Contract(Staking.address, removedABI, graph.provider)

  describe('> Storage variables', () => {
    it(`channelDisputeEpochs should not exist`, async function () {
      await expect(deployedStaking.channelDisputeEpochs()).to.eventually.be.rejected
    })
    it(`rebates should not exist`, async function () {
      await expect(deployedStaking.rebates(123)).to.eventually.be.rejected
    })
  })

  describe('> Allocation state transitions', () => {
    it('Null allocations should remain Null', async function () {
      for (const allocation of allocations.filter((a) => a.state === AllocationState.Null)) {
        await expect(Staking.getAllocationState(allocation.id)).to.eventually.equal(
          AllocationState.Null,
        )
      }
    })

    it('Active allocations should remain Active', async function () {
      for (const allocation of allocations.filter((a) => a.state === AllocationState.Active)) {
        await expect(Staking.getAllocationState(allocation.id)).to.eventually.equal(
          AllocationState.Active,
        )
      }
    })

    it('Closed allocations should remain Closed', async function () {
      for (const allocation of allocations.filter((a) => a.state === AllocationState.Closed)) {
        await expect(Staking.getAllocationState(allocation.id)).to.eventually.equal(
          AllocationState.Closed,
        )
      }
    })

    it('Finalized allocations should transition to Closed', async function () {
      for (const allocation of allocations.filter((a) => a.state === AllocationState.Finalized)) {
        await expect(Staking.getAllocationState(allocation.id)).to.eventually.equal(
          AllocationState.Closed,
        )
      }
    })

    it('Claimed allocations should transition to Closed', async function () {
      for (const allocation of allocations.filter((a) => a.state === AllocationState.Claimed)) {
        await expect(Staking.getAllocationState(allocation.id)).to.eventually.equal(
          AllocationState.Closed,
        )
      }
    })
  })
})

import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { Contract } from 'ethers'
import hre from 'hardhat'

import removedABI from './abis/staking'

chai.use(chaiAsPromised)

describe('Exponential rebates upgrade', () => {
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
})

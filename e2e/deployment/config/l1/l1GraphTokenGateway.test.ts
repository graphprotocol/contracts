import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L1] L1GraphTokenGateway configuration', () => {
  const {
    contracts: { Controller, L1GraphTokenGateway },
  } = hre.graph()

  before(async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (chainIdIsL2(chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await L1GraphTokenGateway.controller()
    expect(controller).eq(Controller.address)
  })
})

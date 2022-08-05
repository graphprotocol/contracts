import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L2] L2Reservoir configuration', () => {
  const {
    contracts: { Controller, L2Reservoir },
  } = hre.graph()

  before(async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (!chainIdIsL2(chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await L2Reservoir.controller()
    expect(controller).eq(Controller.address)
  })
})

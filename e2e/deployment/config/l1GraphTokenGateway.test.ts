import { expect } from 'chai'
import hre from 'hardhat'

describe('L1GraphTokenGateway configuration', () => {
  const {
    contracts: { Controller, L1GraphTokenGateway },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await L1GraphTokenGateway.controller()
    expect(controller).eq(Controller.address)
  })
})

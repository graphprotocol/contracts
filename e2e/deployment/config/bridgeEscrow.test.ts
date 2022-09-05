import { expect } from 'chai'
import hre from 'hardhat'

describe('BridgeEscrow configuration', () => {
  const {
    contracts: { Controller, BridgeEscrow },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await BridgeEscrow.controller()
    expect(controller).eq(Controller.address)
  })
})

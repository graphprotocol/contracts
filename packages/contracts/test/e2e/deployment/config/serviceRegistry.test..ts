import { expect } from 'chai'
import hre from 'hardhat'

describe('ServiceRegistry configuration', () => {
  const {
    contracts: { ServiceRegistry, Controller },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await ServiceRegistry.controller()
    expect(controller).eq(Controller.address)
  })
})

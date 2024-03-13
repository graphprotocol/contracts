import { expect } from 'chai'
import hre from 'hardhat'

describe('RewardsManager configuration', () => {
  const {
    contracts: { RewardsManager, Controller },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await RewardsManager.controller()
    expect(controller).eq(Controller.address)
  })
})

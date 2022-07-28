import { expect } from 'chai'
import hre from 'hardhat'

describe('Protocol configuration', () => {
  const { contracts } = hre.graph()

  it('should be unpaused', async function () {
    const paused = await contracts.Controller.paused()
    expect(paused).eq(false)
  })
})

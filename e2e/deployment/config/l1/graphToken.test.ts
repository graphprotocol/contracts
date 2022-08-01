import { expect } from 'chai'
import hre from 'hardhat'

describe('GraphToken configuration', () => {
  const {
    contracts: { GraphToken, L1Reservoir },
  } = hre.graph()

  it('L1Reservoir should be a minter', async function () {
    const deployerIsMinter = await GraphToken.isMinter(L1Reservoir.address)
    expect(deployerIsMinter).eq(true)
  })
})

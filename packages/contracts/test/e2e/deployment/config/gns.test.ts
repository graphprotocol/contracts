import { expect } from 'chai'
import hre from 'hardhat'

describe('GNS configuration', () => {
  const {
    contracts: { Controller, GNS, SubgraphNFT },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await GNS.controller()
    expect(controller).eq(Controller.address)
  })

  it('subgraphNFT should match the SubgraphNFT deployment address', async function () {
    const subgraphNFT = await GNS.subgraphNFT()
    expect(subgraphNFT).eq(SubgraphNFT.address)
  })
})

import { expect } from 'chai'
import hre from 'hardhat'

describe('GNS configuration', () => {
  const {
    contracts: { Controller, GNS, BancorFormula, SubgraphNFT },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await GNS.controller()
    expect(controller).eq(Controller.address)
  })

  it('bondingCurve should match the BancorFormula deployment address', async function () {
    const bondingCurve = await GNS.bondingCurve()
    expect(bondingCurve).eq(BancorFormula.address)
  })

  it('subgraphNFT should match the SubgraphNFT deployment address', async function () {
    const subgraphNFT = await GNS.subgraphNFT()
    expect(subgraphNFT).eq(SubgraphNFT.address)
  })
})

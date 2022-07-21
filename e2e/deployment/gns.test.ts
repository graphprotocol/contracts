import { expect } from 'chai'
import hre from 'hardhat'

describe('GNS deployment', () => {
  const {
    contracts: { Controller, GNS, BancorFormula, SubgraphNFT, GraphToken, Curation },
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

  it('should allow Curation contract to spend MAX_UINT256 tokens on GNS behalf', async function () {
    const allowance = await GraphToken.allowance(GNS.address, Curation.address)
    expect(allowance).eq(hre.ethers.constants.MaxUint256)
  })
})

import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue, isGraphL2ChainId } from '@graphprotocol/sdk'

describe('[L1] Curation configuration', () => {
  const graph = hre.graph()
  const {
    graphConfig,
    contracts: { Controller, Curation, BancorFormula, GraphCurationToken },
  } = graph

  before(function () {
    if (isGraphL2ChainId(graph.chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await Curation.controller()
    expect(controller).eq(Controller.address)
  })

  it('bondingCurve should match the BancorFormula deployment address', async function () {
    const bondingCurve = await Curation.bondingCurve()
    expect(bondingCurve).eq(BancorFormula.address)
  })

  it('curationTokenMaster should match the GraphCurationToken deployment address', async function () {
    const bondingCurve = await Curation.curationTokenMaster()
    expect(bondingCurve).eq(GraphCurationToken.address)
  })

  it('defaultReserveRatio should match "reserveRatio" in the config file', async function () {
    const value = await Curation.defaultReserveRatio()
    const expected = getItemValue(graphConfig, 'contracts/Curation/init/reserveRatio')
    expect(value).eq(expected)
  })

  it('curationTaxPercentage should match "curationTaxPercentage" in the config file', async function () {
    const value = await Curation.curationTaxPercentage()
    const expected = getItemValue(graphConfig, 'contracts/Curation/init/curationTaxPercentage')
    expect(value).eq(expected)
  })

  it('minimumCurationDeposit should match "minimumCurationDeposit" in the config file', async function () {
    const value = await Curation.minimumCurationDeposit()
    const expected = getItemValue(graphConfig, 'contracts/Curation/init/minimumCurationDeposit')
    expect(value).eq(expected)
  })
})

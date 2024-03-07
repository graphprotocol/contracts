import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue, isGraphL1ChainId } from '@graphprotocol/sdk'

describe('[L2] L2Curation configuration', () => {
  const graph = hre.graph()
  const {
    graphConfig,
    contracts: { Controller, L2Curation, GraphCurationToken },
  } = graph

  before(function () {
    if (isGraphL1ChainId(graph.chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await L2Curation.controller()
    expect(controller).eq(Controller.address)
  })

  it('curationTokenMaster should match the GraphCurationToken deployment address', async function () {
    const gct = await L2Curation.curationTokenMaster()
    expect(gct).eq(GraphCurationToken.address)
  })

  it('defaultReserveRatio should be a constant 1000000', async function () {
    const value = await L2Curation.defaultReserveRatio()
    const expected = 1000000
    expect(value).eq(expected)
  })

  it('curationTaxPercentage should match "curationTaxPercentage" in the config file', async function () {
    const value = await L2Curation.curationTaxPercentage()
    const expected = getItemValue(graphConfig, 'contracts/L2Curation/init/curationTaxPercentage')
    expect(value).eq(expected)
  })

  it('minimumCurationDeposit should match "minimumCurationDeposit" in the config file', async function () {
    const value = await L2Curation.minimumCurationDeposit()
    const expected = getItemValue(graphConfig, 'contracts/L2Curation/init/minimumCurationDeposit')
    expect(value).eq(expected)
  })
})

import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/network'
import { getItemValue } from '../../../../cli/config'

describe('[L1] L1Reservoir configuration', () => {
  const graph = hre.graph()
  const { graphConfig } = graph
  const { L1Reservoir, Controller, GraphToken, RewardsManager } = graph.contracts

  before(async function () {
    if (GraphChain.isL2(graph.chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await L1Reservoir.controller()
    expect(controller).eq(Controller.address)
  })

  it('should have a snapshot of the total supply', async function () {
    expect(await L1Reservoir.issuanceBase()).eq(await GraphToken.totalSupply())
  })

  it('should have issuanceRate set to zero', async function () {
    expect(await L1Reservoir.issuanceRate()).eq(0)
  })

  it('should have dripInterval set from config', async function () {
    const value = await L1Reservoir.dripInterval()
    const expected = getItemValue(graphConfig, 'contracts/L1Reservoir/init/dripInterval')
    expect(value).eq(expected)
  })

  it('should have RewardsManager approved for the max GRT amount', async function () {
    expect(await GraphToken.allowance(L1Reservoir.address, RewardsManager.address)).eq(
      hre.ethers.constants.MaxUint256,
    )
  })
})

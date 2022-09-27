import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/network'
import { getItemValue } from '../../../../cli/config'

describe('[L2] L2Reservoir configuration', () => {
  const graph = hre.graph()
  const { graphConfig } = graph
  const { L2Reservoir, Controller, GraphToken, RewardsManager } = graph.contracts

  before(async function () {
    if (GraphChain.isL1(graph.chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await L2Reservoir.controller()
    expect(controller).eq(Controller.address)
  })

  it('should have issuanceBase set to zero', async function () {
    expect(await L2Reservoir.issuanceBase()).eq(0)
  })

  it('should have issuanceRate set to zero', async function () {
    expect(await L2Reservoir.issuanceRate()).eq(0)
  })

  it('should have RewardsManager approved for the max GRT amount', async function () {
    expect(await GraphToken.allowance(L2Reservoir.address, RewardsManager.address)).eq(
      hre.ethers.constants.MaxUint256,
    )
  })
})

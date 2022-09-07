import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/network'

describe('[L2] L2GraphTokenGateway configuration', function () {
  const graph = hre.graph()
  const { Controller, L2GraphTokenGateway } = graph.contracts

  before(async function () {
    if (GraphChain.isL1(graph.chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await L2GraphTokenGateway.controller()
    expect(controller).eq(Controller.address)
  })
})

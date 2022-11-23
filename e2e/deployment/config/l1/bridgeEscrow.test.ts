import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/chain'

describe('[L1] BridgeEscrow configuration', function () {
  const graph = hre.graph()
  const { Controller, BridgeEscrow } = graph.contracts

  before(async function () {
    if (GraphChain.isL2(graph.chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await BridgeEscrow.controller()
    expect(controller).eq(Controller.address)
  })
})

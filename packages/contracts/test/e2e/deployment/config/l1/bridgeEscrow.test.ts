import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL2ChainId } from '@graphprotocol/sdk'

describe('[L1] BridgeEscrow configuration', function () {
  const graph = hre.graph()
  const { Controller, BridgeEscrow } = graph.contracts

  before(async function () {
    if (isGraphL2ChainId(graph.chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await BridgeEscrow.controller()
    expect(controller).eq(Controller.address)
  })
})

import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL1ChainId } from '@graphprotocol/sdk'

describe('[L2] GNS', () => {
  const graph = hre.graph()
  const { L2GNS } = graph.l2.contracts

  before(function () {
    if (isGraphL1ChainId(graph.chainId)) this.skip()
  })

  describe('L2GNS', () => {
    it('counterpartGNSAddress should match the L1GNS address', async () => {
      const l1GNS = await L2GNS.counterpartGNSAddress()
      expect(l1GNS).eq(graph.l1.contracts.L1GNS.address)
    })
  })
})

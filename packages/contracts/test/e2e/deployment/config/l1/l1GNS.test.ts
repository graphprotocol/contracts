import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL2ChainId } from '@graphprotocol/sdk'

describe('[L1] GNS', () => {
  const graph = hre.graph()
  const { L1GNS, L1GraphTokenGateway } = graph.contracts

  let unauthorized: SignerWithAddress

  before(async function () {
    if (isGraphL2ChainId(graph.chainId)) this.skip()
    unauthorized = (await graph.getTestAccounts())[0]
  })

  describe('L1GNS', () => {
    it('counterpartGNSAddress should match the L2GNS address', async () => {
      const l2GNS = await L1GNS.counterpartGNSAddress()
      expect(l2GNS).eq(graph.l2.contracts.L2GNS.address)
    })

    it('should be added to callhookAllowlist', async () => {
      const isAllowed = await L1GraphTokenGateway.callhookAllowlist(L1GNS.address)
      expect(isAllowed).true
    })
  })
})

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/network'

describe('[L2] L2GraphTokenGateway configuration', function () {
  const graph = hre.graph()
  const { Controller, L2GraphTokenGateway } = graph.contracts

  let unauthorized: SignerWithAddress
  before(async function () {
    if (GraphChain.isL1(graph.chainId)) this.skip()
    unauthorized = (await graph.getTestAccounts())[0]
  })

  it('bridge should be paused', async function () {
    const paused = await L2GraphTokenGateway.paused()
    expect(paused).eq(true)
  })

  it('should be controlled by Controller', async function () {
    const controller = await L2GraphTokenGateway.controller()
    expect(controller).eq(Controller.address)
  })

  describe('calls with unauthorized user', () => {
    it('initialize should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).initialize(unauthorized.address)
      await expect(tx).revertedWith('Caller must be the implementation')
    })

    it('setL2Router should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).setL2Router(unauthorized.address)
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('setL1TokenAddress should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).setL1TokenAddress(unauthorized.address)
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('setL1CounterpartAddress should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).setL1CounterpartAddress(
        unauthorized.address,
      )
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('finalizeInboundTransfer should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).finalizeInboundTransfer(
        unauthorized.address,
        unauthorized.address,
        unauthorized.address,
        '1000000000000',
        '0x00',
      )

      await expect(tx).revertedWith('Paused (contract)')
    })
  })
})

import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/network'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

describe('[L1] L1GraphTokenGateway configuration', function () {
  const graph = hre.graph()
  const { Controller, L1GraphTokenGateway } = graph.contracts

  let unauthorized: SignerWithAddress
  before(async function () {
    if (GraphChain.isL2(graph.chainId)) this.skip()
    unauthorized = (await graph.getTestAccounts())[0]
  })

  it('bridge should be paused', async function () {
    const paused = await L1GraphTokenGateway.paused()
    expect(paused).eq(true)
  })

  it('should be controlled by Controller', async function () {
    const controller = await L1GraphTokenGateway.controller()
    expect(controller).eq(Controller.address)
  })

  describe('calls with unauthorized user', () => {
    it('initialize should revert', async function () {
      const tx = L1GraphTokenGateway.connect(unauthorized).initialize(unauthorized.address)
      await expect(tx).revertedWith('Caller must be the implementation')
    })

    it('setArbitrumAddresses should revert', async function () {
      const tx = L1GraphTokenGateway.connect(unauthorized).setArbitrumAddresses(
        unauthorized.address,
        unauthorized.address,
      )
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('setL2TokenAddress should revert', async function () {
      const tx = L1GraphTokenGateway.connect(unauthorized).setL2TokenAddress(unauthorized.address)
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('setL2CounterpartAddress should revert', async function () {
      const tx = L1GraphTokenGateway.connect(unauthorized).setL2CounterpartAddress(
        unauthorized.address,
      )
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('setEscrowAddress should revert', async function () {
      const tx = L1GraphTokenGateway.connect(unauthorized).setEscrowAddress(unauthorized.address)
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('addToCallhookWhitelist should revert', async function () {
      const tx = L1GraphTokenGateway.connect(unauthorized).addToCallhookWhitelist(
        unauthorized.address,
      )
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('removeFromCallhookWhitelist should revert', async function () {
      const tx = L1GraphTokenGateway.connect(unauthorized).removeFromCallhookWhitelist(
        unauthorized.address,
      )
      await expect(tx).revertedWith('Caller must be Controller governor')
    })

    it('finalizeInboundTransfer should revert', async function () {
      const tx = L1GraphTokenGateway.connect(unauthorized).finalizeInboundTransfer(
        unauthorized.address,
        unauthorized.address,
        unauthorized.address,
        '100',
        '0x00',
      )

      await expect(tx).revertedWith('Paused (contract)')
    })
  })
})

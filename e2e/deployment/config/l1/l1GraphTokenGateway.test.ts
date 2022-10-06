import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/network'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { getAddressBook } from '../../../../cli/address-book'

describe('[L1] L1GraphTokenGateway configuration', function () {
  const graph = hre.graph()
  const { Controller, L1GraphTokenGateway } = graph.contracts

  let unauthorized: SignerWithAddress
  before(async function () {
    if (GraphChain.isL2(graph.chainId)) this.skip()
    unauthorized = (await graph.getTestAccounts())[0]
  })

  it('bridge should be unpaused', async function () {
    const paused = await L1GraphTokenGateway.paused()
    expect(paused).eq(false)
  })

  it('should be controlled by Controller', async function () {
    const controller = await L1GraphTokenGateway.controller()
    expect(controller).eq(Controller.address)
  })

  it('l2GRT should match the L2 GraphToken deployed address', async function () {
    const l2GRT = await L1GraphTokenGateway.l2GRT()
    expect(l2GRT).eq(graph.l2.contracts.GraphToken.address)
  })

  it('l2Counterpart should match the deployed L2 GraphTokenGateway address', async function () {
    const l2Counterpart = await L1GraphTokenGateway.l2Counterpart()
    expect(l2Counterpart).eq(graph.l2.contracts.L2GraphTokenGateway.address)
  })

  it('escrow should match the deployed L1 BridgeEscrow address', async function () {
    const escrow = await L1GraphTokenGateway.escrow()
    expect(escrow).eq(graph.l1.contracts.BridgeEscrow.address)
  })

  it("inbox should match Arbitrum's Inbox address", async function () {
    const inbox = await L1GraphTokenGateway.inbox()

    // TODO: is there a cleaner way to get the router address?
    const arbitrumAddressBook = process.env.ARBITRUM_ADDRESS_BOOK ?? 'arbitrum-addresses-local.json'
    const arbAddressBook = getAddressBook(arbitrumAddressBook, graph.l1.chainId.toString())
    const arbIInbox = arbAddressBook.getEntry('IInbox')

    expect(inbox.toLowerCase()).eq(arbIInbox.address.toLowerCase())
  })

  it("l1Router should match Arbitrum's router address", async function () {
    const l1Router = await L1GraphTokenGateway.l1Router()

    // TODO: is there a cleaner way to get the router address?
    const arbitrumAddressBook = process.env.ARBITRUM_ADDRESS_BOOK ?? 'arbitrum-addresses-local.json'
    const arbAddressBook = getAddressBook(arbitrumAddressBook, graph.l1.chainId.toString())
    const arbL2Router = arbAddressBook.getEntry('L1GatewayRouter')

    expect(l1Router).eq(arbL2Router.address)
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

      await expect(tx).revertedWith('NOT_FROM_BRIDGE')
    })
  })
})

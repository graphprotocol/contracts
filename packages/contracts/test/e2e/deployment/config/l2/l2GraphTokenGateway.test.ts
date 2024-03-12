import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL1ChainId, SimpleAddressBook } from '@graphprotocol/sdk'

describe('[L2] L2GraphTokenGateway configuration', function () {
  const graph = hre.graph()
  const { Controller, L2GraphTokenGateway } = graph.contracts

  let unauthorized: SignerWithAddress
  before(async function () {
    if (isGraphL1ChainId(graph.chainId)) this.skip()
    unauthorized = (await graph.getTestAccounts())[0]
  })

  it('bridge should not be paused', async function () {
    const paused = await L2GraphTokenGateway.paused()
    expect(paused).eq(false)
  })

  it('should be controlled by Controller', async function () {
    const controller = await L2GraphTokenGateway.controller()
    expect(controller).eq(Controller.address)
  })

  it('l1GRT should match the L1 GraphToken deployed address', async function () {
    const l1GRT = await L2GraphTokenGateway.l1GRT()
    expect(l1GRT).eq(graph.l1.contracts.GraphToken.address)
  })

  it('l1Counterpart should match the deployed L1 GraphTokenGateway address', async function () {
    const l1Counterpart = await L2GraphTokenGateway.l1Counterpart()
    expect(l1Counterpart).eq(graph.l1.contracts.L1GraphTokenGateway.address)
  })

  it('l2Router should match Arbitrum\'s router address', async function () {
    const l2Router = await L2GraphTokenGateway.l2Router()

    // TODO: is there a cleaner way to get the router address?
    const arbitrumAddressBook = process.env.ARBITRUM_ADDRESS_BOOK ?? 'arbitrum-addresses-local.json'
    const arbAddressBook = new SimpleAddressBook(arbitrumAddressBook, graph.l2.chainId)
    const arbL2Router = arbAddressBook.getEntry('L2GatewayRouter')

    expect(l2Router).eq(arbL2Router.address)
  })

  describe('calls with unauthorized user', () => {
    it('initialize should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).initialize(unauthorized.address)
      await expect(tx).revertedWith('Only implementation')
    })

    it('setL2Router should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).setL2Router(unauthorized.address)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('setL1TokenAddress should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).setL1TokenAddress(unauthorized.address)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('setL1CounterpartAddress should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).setL1CounterpartAddress(
        unauthorized.address,
      )
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('finalizeInboundTransfer should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized).finalizeInboundTransfer(
        unauthorized.address,
        unauthorized.address,
        unauthorized.address,
        '1000000000000',
        '0x00',
      )

      await expect(tx).revertedWith('ONLY_COUNTERPART_GATEWAY')
    })
  })
})

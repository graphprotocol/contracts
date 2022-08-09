import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L1] L1GraphTokenGateway configuration', () => {
  const {
    contracts: { Controller, L1GraphTokenGateway },
    getTestAccounts,
  } = hre.graph()

  let unauthorized: SignerWithAddress

  before(async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (chainIdIsL2(chainId)) this.skip()

    unauthorized = (await getTestAccounts())[0]
  })

  it('bridge should be unpaused', async function () {
    const paused = await L1GraphTokenGateway.paused()
    expect(paused).eq(false)
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

      await expect(tx).revertedWith('ONLY_COUNTERPART_GATEWAY')
    })
  })
})

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L2] L2GraphTokenGateway configuration', () => {
  const {
    contracts: { Controller, L2GraphTokenGateway },
    getTestAccounts,
  } = hre.graph()

  let unauthorized: SignerWithAddress

  before(async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (!chainIdIsL2(chainId)) this.skip()

    unauthorized = (await getTestAccounts())[0]
  })

  it('bridge should be unpaused', async function () {
    const paused = await L2GraphTokenGateway.paused()
    expect(paused).eq(false)
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

      await expect(tx).revertedWith('ONLY_COUNTERPART_GATEWAY')
    })
  })
})

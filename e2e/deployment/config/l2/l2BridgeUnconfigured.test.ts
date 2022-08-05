import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L2] L2 bridge auth protection', () => {
  const {
    contracts: { L2GraphToken, L2GraphTokenGateway },
    getTestAccounts,
  } = hre.graph()

  let unauthorized: SignerWithAddress

  before(async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (!chainIdIsL2(chainId)) this.skip()

    unauthorized = (await getTestAccounts())[0]
  })

  describe('L2GraphToken calls with unauthorized user', () => {
    it('mint should revert', async function () {
      const tx = L2GraphToken.connect(unauthorized).mint(
        unauthorized.address,
        '1000000000000000000000',
      )
      await expect(tx).revertedWith('Only minter can call')
    })

    it('bridgeMint should revert', async function () {
      const tx = L2GraphToken.connect(unauthorized).bridgeMint(
        unauthorized.address,
        '1000000000000000000000',
      )
      await expect(tx).revertedWith('NOT_GATEWAY')
    })

    it('setGateway should revert', async function () {
      const tx = L2GraphToken.connect(unauthorized).setGateway(unauthorized.address)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('L2GraphTokenGateway calls with unauthorized user', () => {
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

    it('outboundTransfer should revert', async function () {
      const tx = L2GraphTokenGateway.connect(unauthorized)[
        'outboundTransfer(address,address,uint256,uint256,uint256,bytes)'
      ](L2GraphToken.address, unauthorized.address, '1000000000000', 0, 0, '0x00')

      await expect(tx).revertedWith('TOKEN_NOT_GRT')
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

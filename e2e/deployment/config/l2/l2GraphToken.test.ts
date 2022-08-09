import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L2] L2GraphToken', () => {
  const {
    contracts: { L2GraphToken },
    getTestAccounts,
  } = hre.graph()

  let unauthorized: SignerWithAddress

  before(async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (!chainIdIsL2(chainId)) this.skip()

    unauthorized = (await getTestAccounts())[0]
  })

  describe('calls with unauthorized user', () => {
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
})

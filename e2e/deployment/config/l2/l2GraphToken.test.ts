import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/network'

describe('[L2] L2GraphToken', () => {
  const graph = hre.graph()
  const { L2GraphToken } = graph.contracts

  let unauthorized: SignerWithAddress

  before(async function () {
    if (GraphChain.isL1(graph.chainId)) this.skip()
    unauthorized = (await graph.getTestAccounts())[0]
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

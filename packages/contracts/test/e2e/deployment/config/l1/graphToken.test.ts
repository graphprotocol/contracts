import { isGraphL2ChainId } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'

describe('[L1] GraphToken', () => {
  const graph = hre.graph()
  const { GraphToken, RewardsManager } = graph.contracts

  let unauthorized: SignerWithAddress

  before(async function () {
    if (isGraphL2ChainId(graph.chainId)) this.skip()
    unauthorized = (await graph.getTestAccounts())[0]
  })

  describe('calls with unauthorized user', () => {
    it('mint should revert', async function () {
      const tx = GraphToken.connect(unauthorized).mint(
        unauthorized.address,
        '1000000000000000000000',
      )
      await expect(tx).revertedWith('Only minter can call')
    })

    it('RewardsManager should be minter', async function () {
      const rewardsMgrIsMinter = await GraphToken.isMinter(RewardsManager.address)
      expect(rewardsMgrIsMinter).eq(true)
    })
  })
})

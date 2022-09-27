import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/network'

describe('[L1] GraphToken', () => {
  const graph = hre.graph()
  const { GraphToken, L1Reservoir, RewardsManager } = graph.contracts

  let unauthorized: SignerWithAddress

  before(async function () {
    if (GraphChain.isL2(graph.chainId)) this.skip()
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

    it('L1Reservoir should be minter', async function () {
      const reservoirIsMinter = await GraphToken.isMinter(L1Reservoir.address)
      expect(reservoirIsMinter).eq(true)
    })

    it('RewardsManager should not be minter', async function () {
      const rewardsMgrIsMinter = await GraphToken.isMinter(RewardsManager.address)
      expect(rewardsMgrIsMinter).eq(false)
    })
  })
})

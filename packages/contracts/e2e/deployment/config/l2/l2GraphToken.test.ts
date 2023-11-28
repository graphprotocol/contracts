import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL1ChainId } from '@graphprotocol/sdk'

describe('[L2] L2GraphToken', () => {
  const graph = hre.graph()
  const { L2GraphToken, RewardsManager } = graph.contracts

  let unauthorized: SignerWithAddress

  before(async function () {
    if (isGraphL1ChainId(graph.chainId)) this.skip()
    unauthorized = (await graph.getTestAccounts())[0]
  })

  it('l1Address should match the L1 GraphToken deployed address', async function () {
    const l1Address = await L2GraphToken.l1Address()
    expect(l1Address).eq(graph.l1.contracts.GraphToken.address)
  })

  it('gateway should match the L2 GraphTokenGateway deployed address', async function () {
    const gateway = await L2GraphToken.gateway()
    expect(gateway).eq(graph.l2.contracts.L2GraphTokenGateway.address)
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

    it('RewardsManager should be minter', async function () {
      const rewardsMgrIsMinter = await L2GraphToken.isMinter(RewardsManager.address)
      expect(rewardsMgrIsMinter).eq(true)
    })
  })
})

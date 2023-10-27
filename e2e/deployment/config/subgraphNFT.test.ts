import { expect } from 'chai'
import hre from 'hardhat'
import { NamedAccounts } from '@graphprotocol/sdk/gre'

describe('SubgraphNFT configuration', () => {
  const {
    getNamedAccounts,
    contracts: { SubgraphNFT, GNS, SubgraphNFTDescriptor },
  } = hre.graph()

  let namedAccounts: NamedAccounts

  before(async () => {
    namedAccounts = await getNamedAccounts()
  })

  it('should be owned by governor', async function () {
    const owner = await SubgraphNFT.governor()
    expect(owner).eq(namedAccounts.governor.address)
  })

  it('should allow GNS to mint NFTs', async function () {
    const minter = await SubgraphNFT.minter()
    expect(minter).eq(GNS.address)
  })

  it('tokenDescriptor should match the SubgraphNFTDescriptor deployment address', async function () {
    const tokenDescriptor = await SubgraphNFT.tokenDescriptor()
    expect(tokenDescriptor).eq(SubgraphNFTDescriptor.address)
  })
})

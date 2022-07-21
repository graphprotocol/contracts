import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../cli/config'

describe('SubgraphNFT deployment', () => {
  const {
    graphConfig,
    contracts: { SubgraphNFT, GNS, SubgraphNFTDescriptor },
  } = hre.graph()

  it('should be owned by governor', async function () {
    const owner = await SubgraphNFT.governor()
    const governorAddress = getItemValue(graphConfig, 'general/governor')
    expect(owner).eq(governorAddress)
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

import { expect } from 'chai'
import hre from 'hardhat'

describe('GNS initialization', () => {
  const {
    contracts: { GNS, GraphToken, Curation },
  } = hre.graph()

  it('should allow Curation contract to spend MAX_UINT256 tokens on GNS behalf', async function () {
    const allowance = await GraphToken.allowance(GNS.address, Curation.address)
    expect(allowance).eq(hre.ethers.constants.MaxUint256)
  })
})

import { expect } from 'chai'
import hre from 'hardhat'

describe('AllocationExchange initialization', () => {
  const {
    contracts: { AllocationExchange, GraphToken, Staking },
  } = hre.graph()

  it('should allow Staking contract to spend MAX_UINT256 tokens on AllocationExchange behalf', async function () {
    const allowance = await GraphToken.allowance(AllocationExchange.address, Staking.address)
    expect(allowance).eq(hre.ethers.constants.MaxUint256)
  })
})

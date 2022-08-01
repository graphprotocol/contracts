import { expect } from 'chai'
import hre from 'hardhat'

describe('L1Reservoir initialization', () => {
  const {
    contracts: { L1Reservoir, GraphToken, RewardsManager },
  } = hre.graph()

  it('should allow RewardsManager contract to spend MAX_UINT256 tokens on L1Reservoirs behalf', async function () {
    const allowance = await GraphToken.allowance(L1Reservoir.address, RewardsManager.address)
    expect(allowance).eq(hre.ethers.constants.MaxUint256)
  })
})

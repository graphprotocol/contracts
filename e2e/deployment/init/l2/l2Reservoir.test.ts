import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L2] L2Reservoir initialization', () => {
  const {
    contracts: { L2Reservoir, GraphToken, RewardsManager },
  } = hre.graph()

  before(async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (!chainIdIsL2(chainId)) this.skip()
  })

  it('should allow RewardsManager contract to spend MAX_UINT256 tokens on L1Reservoirs behalf', async function () {
    const allowance = await GraphToken.allowance(L2Reservoir.address, RewardsManager.address)
    expect(allowance).eq(hre.ethers.constants.MaxUint256)
  })
})

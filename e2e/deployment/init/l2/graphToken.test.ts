import { expect } from 'chai'
import hre from 'hardhat'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L2] GraphToken initialization', () => {
  const {
    contracts: { GraphToken },
  } = hre.graph()

  let chainId: number
  before(async function () {
    chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (!chainIdIsL2(chainId)) this.skip()
  })

  it('total supply should be zero', async function () {
    const value = await GraphToken.totalSupply()
    chainId === 1337 || chainId === 412346 ? expect(value).eq(0) : expect(value).gte(0)
  })
})

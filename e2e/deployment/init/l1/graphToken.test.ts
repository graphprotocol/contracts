import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../../../cli/config'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L1] GraphToken initialization', () => {
  const {
    graphConfig,
    contracts: { GraphToken },
  } = hre.graph()

  let chainId: number
  before(async function () {
    chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (chainIdIsL2(chainId)) this.skip()
  })

  it('total supply should match "initialSupply" on the config file', async function () {
    const value = await GraphToken.totalSupply()
    const expected = getItemValue(graphConfig, 'contracts/GraphToken/init/initialSupply')

    chainId === 1337 || chainId === 412346
      ? expect(value).eq(expected)
      : expect(value).gte(expected)
  })
})

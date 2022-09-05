import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../../../cli/config'

describe('GraphToken initialization', () => {
  const {
    graphConfig,
    contracts: { GraphToken },
  } = hre.graph()

  it('total supply should match "initialSupply" on the config file', async function () {
    const value = await GraphToken.totalSupply()
    const expected = getItemValue(graphConfig, 'contracts/GraphToken/init/initialSupply')
    hre.network.config.chainId === 1337 ? expect(value).eq(expected) : expect(value).gte(expected)
  })
})

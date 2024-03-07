import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue, isGraphL2ChainId } from '@graphprotocol/sdk'

describe('[L1] GraphToken initialization', () => {
  const graph = hre.graph()
  const { GraphToken } = graph.contracts

  before(function () {
    if (isGraphL2ChainId(graph.chainId)) this.skip()
  })

  it('total supply should match "initialSupply" on the config file', async function () {
    const value = await GraphToken.totalSupply()
    const expected = getItemValue(graph.graphConfig, 'contracts/GraphToken/init/initialSupply')
    expect(value).eq(expected)
  })
})

import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../../../cli/config'
import GraphChain from '../../../../gre/helpers/chain'

describe('[L1] GraphToken initialization', () => {
  const graph = hre.graph()
  const { GraphToken } = graph.contracts

  before(async function () {
    if (GraphChain.isL2(graph.chainId)) this.skip()
  })

  it('total supply should match "initialSupply" on the config file', async function () {
    const value = await GraphToken.totalSupply()
    const expected = getItemValue(graph.graphConfig, 'contracts/GraphToken/init/initialSupply')
    expect(value).eq(expected)
  })
})

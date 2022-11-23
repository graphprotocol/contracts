import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/chain'

describe('[L2] GraphToken initialization', () => {
  const graph = hre.graph()
  const { GraphToken } = graph.contracts

  before(async function () {
    if (GraphChain.isL1(graph.chainId)) this.skip()
  })

  it('total supply should be zero', async function () {
    const value = await GraphToken.totalSupply()
    expect(value).eq(0)
  })
})

import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL1ChainId } from '@graphprotocol/sdk'

describe('[L2] GraphToken initialization', () => {
  const graph = hre.graph()
  const { GraphToken } = graph.contracts

  before(function () {
    if (isGraphL1ChainId(graph.chainId)) this.skip()
  })

  it('total supply should be zero', async function () {
    const value = await GraphToken.totalSupply()
    expect(value).eq(0)
  })
})

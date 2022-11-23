import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/chain'

describe('[L2] RewardsManager configuration', () => {
  const graph = hre.graph()
  const { RewardsManager } = graph.contracts

  before(async function () {
    if (GraphChain.isL1(graph.chainId)) this.skip()
  })

  it('issuanceRate should be zero', async function () {
    const value = await RewardsManager.issuanceRate()
    expect(value).eq('0')
  })
})

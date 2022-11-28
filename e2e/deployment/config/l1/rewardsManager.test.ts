import { expect } from 'chai'
import hre from 'hardhat'
import GraphChain from '../../../../gre/helpers/chain'

describe('[L1] RewardsManager configuration', () => {
  const graph = hre.graph()
  const { RewardsManager } = graph.contracts

  before(async function () {
    if (GraphChain.isL2(graph.chainId)) this.skip()
  })

  it('issuanceRate should match "issuanceRate" in the config file', async function () {
    const value = await RewardsManager.issuanceRate()
    expect(value).eq('1000000011247641700') // hardcoded as it's set with a function call rather than init parameter
  })
})

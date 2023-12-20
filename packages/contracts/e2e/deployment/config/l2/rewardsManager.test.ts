import { isGraphL1ChainId } from '@graphprotocol/sdk'
import { expect } from 'chai'
import hre from 'hardhat'

describe('[L2] RewardsManager configuration', () => {
  const graph = hre.graph()
  const { RewardsManager } = graph.contracts

  before(async function () {
    if (isGraphL1ChainId(graph.chainId)) this.skip()
  })

  it('issuancePerBlock should be zero', async function () {
    const value = await RewardsManager.issuancePerBlock()
    expect(value).eq('6036500000000000000') // hardcoded as it's set with a function call rather than init parameter
  })
})

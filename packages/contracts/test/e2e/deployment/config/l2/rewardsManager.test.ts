import { isGraphL1ChainId } from '@graphprotocol/sdk'
import { expect } from 'chai'
import hre from 'hardhat'

describe('[L2] RewardsManager configuration', () => {
  const graph = hre.graph()
  const { RewardsManager, SubgraphAvailabilityManager } = graph.contracts

  before(function () {
    if (isGraphL1ChainId(graph.chainId)) this.skip()
  })

  it('issuancePerBlock should be zero', async function () {
    const value = await RewardsManager.issuancePerBlock()
    expect(value).eq('6036500000000000000') // hardcoded as it's set with a function call rather than init parameter
  })

  it('should allow subgraph availability manager to deny rewards', async function () {
    const availabilityOracle = await RewardsManager.subgraphAvailabilityOracle()
    expect(availabilityOracle).eq(SubgraphAvailabilityManager.address)
  })
})

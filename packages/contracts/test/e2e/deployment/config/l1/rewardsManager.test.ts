import { expect } from 'chai'
import hre from 'hardhat'
import { isGraphL2ChainId } from '@graphprotocol/sdk'
import { NamedAccounts } from '@graphprotocol/sdk/gre'

describe('[L1] RewardsManager configuration', () => {
  const graph = hre.graph()
  const { RewardsManager } = graph.contracts

  let namedAccounts: NamedAccounts

  before(async function () {
    if (isGraphL2ChainId(graph.chainId)) this.skip()
    namedAccounts = await graph.getNamedAccounts()
  })

  it('issuancePerBlock should match "issuancePerBlock" in the config file', async function () {
    const value = await RewardsManager.issuancePerBlock()
    expect(value).eq('114693500000000000000') // hardcoded as it's set with a function call rather than init parameter
  })

  it('should allow subgraph availability oracle to deny rewards', async function () {
    const availabilityOracle = await RewardsManager.subgraphAvailabilityOracle()
    expect(availabilityOracle).eq(namedAccounts.availabilityOracle.address)
  })
})

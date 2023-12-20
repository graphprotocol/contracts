import { expect } from 'chai'
import hre from 'hardhat'
import { NamedAccounts } from '@graphprotocol/sdk/gre'

describe('RewardsManager configuration', () => {
  const {
    getNamedAccounts,
    contracts: { RewardsManager, Controller },
  } = hre.graph()

  let namedAccounts: NamedAccounts

  before(async () => {
    namedAccounts = await getNamedAccounts()
  })

  it('should be controlled by Controller', async function () {
    const controller = await RewardsManager.controller()
    expect(controller).eq(Controller.address)
  })

  it('should allow subgraph availability oracle to deny rewards', async function () {
    const availabilityOracle = await RewardsManager.subgraphAvailabilityOracle()
    expect(availabilityOracle).eq(namedAccounts.availabilityOracle.address)
  })
})

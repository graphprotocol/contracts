import { expect } from 'chai'
import hre from 'hardhat'
import { NamedAccounts } from '../../../tasks/type-extensions'

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

  it('issuanceRate should match "issuanceRate" in the config file', async function () {
    const value = await RewardsManager.issuanceRate()
    expect(value).eq('1000000012184945188') // hardcoded as it's set with a function call rather than init parameter
  })

  it('should allow subgraph availability oracle to deny rewards', async function () {
    const availabilityOracle = await RewardsManager.subgraphAvailabilityOracle()
    expect(availabilityOracle).eq(namedAccounts.availabilityOracle.address)
  })
})

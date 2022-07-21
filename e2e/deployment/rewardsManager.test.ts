import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../cli/config'

describe('RewardsManager deployment', () => {
  const {
    graphConfig,
    contracts: { RewardsManager, Controller },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await RewardsManager.controller()
    expect(controller).eq(Controller.address)
  })

  it('issuanceRate should match "issuanceRate" in the config file', async function () {
    const value = await RewardsManager.issuanceRate()
    const expected = getItemValue(graphConfig, 'contracts/RewardsManager/init/issuanceRate')
    expect(value).eq(expected)
  })

  it('should allow subgraph availability oracle to deny rewards', async function () {
    const availabilityOracleAddress = getItemValue(graphConfig, 'general/availabilityOracle')
    const availabilityOracle = await RewardsManager.subgraphAvailabilityOracle()
    expect(availabilityOracle).eq(availabilityOracleAddress)
  })
})

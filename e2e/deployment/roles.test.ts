import { expect } from 'chai'
import hre from 'hardhat'
import { getItem, getNode } from '../../cli/config'

describe('Protocol roles', () => {
  const { contracts, graphConfig, addressBook } = hre.graph()

  it('pause guardian should be able to pause protocol', async function () {
    const pauseGuardianAddress = getItem(getNode(graphConfig, ['general']), 'pauseGuardian').value
    const pauseGuardian = await contracts.Controller.pauseGuardian()
    expect(pauseGuardian).eq(pauseGuardianAddress)
  })

  it('allocation exchange should accept vouchers from authority', async function () {
    const authorityAddress = getItem(getNode(graphConfig, ['general']), 'authority').value
    const allowed = await contracts.AllocationExchange.authority(authorityAddress)
    expect(allowed).eq(true)
  })

  it('subgraph availability oracle should be able to deny rewards', async function () {
    const availabilityOracleAddress = getItem(
      getNode(graphConfig, ['general']),
      'availabilityOracle',
    ).value
    const availabilityOracle = await contracts.RewardsManager.subgraphAvailabilityOracle()
    expect(availabilityOracle).eq(availabilityOracleAddress)
  })

  it('arbitrator should be able to resolve disputes', async function () {
    const arbitratorAddress = getItem(getNode(graphConfig, ['general']), 'arbitrator').value
    const arbitrator = await contracts.DisputeManager.arbitrator()
    expect(arbitrator).eq(arbitratorAddress)
  })

  it('allocation exchange should be able to collect query fees', async function () {
    const allocationExchangeAddress = addressBook.getEntry('AllocationExchange').address
    const allowed = await contracts.Staking.assetHolders(allocationExchangeAddress)
    expect(allowed).eq(true)
  })
})

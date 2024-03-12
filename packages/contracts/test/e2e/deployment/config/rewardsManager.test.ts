import { expect } from 'chai'
import hre from 'hardhat'
import { NamedAccounts } from '@graphprotocol/sdk/gre'

describe('RewardsManager configuration', () => {
  const {
    contracts: { RewardsManager, Controller, SubgraphAvailabilityManager },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await RewardsManager.controller()
    expect(controller).eq(Controller.address)
  })

  it('should allow subgraph availability oracle to deny rewards', async function () {
    const availabilityOracle = await RewardsManager.subgraphAvailabilityOracle()
    expect(availabilityOracle).eq(SubgraphAvailabilityManager.address)
  })
})

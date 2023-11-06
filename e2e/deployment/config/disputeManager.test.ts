import { getItemValue } from '@graphprotocol/sdk'
import { expect } from 'chai'
import hre from 'hardhat'

describe('DisputeManager configuration', () => {
  const {
    graphConfig,
    contracts: { Controller, DisputeManager },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await DisputeManager.controller()
    expect(controller).eq(Controller.address)
  })

  it('arbitrator should be able to resolve disputes', async function () {
    const arbitratorAddress = getItemValue(graphConfig, 'general/arbitrator')
    const arbitrator = await DisputeManager.arbitrator()
    expect(arbitrator).eq(arbitratorAddress)
  })

  it('minimumDeposit should match "minimumDeposit" in the config file', async function () {
    const value = await DisputeManager.minimumDeposit()
    const expected = getItemValue(graphConfig, 'contracts/DisputeManager/init/minimumDeposit')
    expect(value).eq(expected)
  })

  it('fishermanRewardPercentage should match "fishermanRewardPercentage" in the config file', async function () {
    const value = await DisputeManager.fishermanRewardPercentage()
    const expected = getItemValue(
      graphConfig,
      'contracts/DisputeManager/init/fishermanRewardPercentage',
    )
    expect(value).eq(expected)
  })

  it('idxSlashingPercentage should match "idxSlashingPercentage" in the config file', async function () {
    const value = await DisputeManager.idxSlashingPercentage()
    const expected = getItemValue(
      graphConfig,
      'contracts/DisputeManager/init/idxSlashingPercentage',
    )
    expect(value).eq(expected)
  })

  it('qrySlashingPercentage should match "qrySlashingPercentage" in the config file', async function () {
    const value = await DisputeManager.qrySlashingPercentage()
    const expected = getItemValue(
      graphConfig,
      'contracts/DisputeManager/init/qrySlashingPercentage',
    )
    expect(value).eq(expected)
  })
})

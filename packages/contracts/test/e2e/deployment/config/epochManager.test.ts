import { getItemValue } from '@graphprotocol/sdk'
import { expect } from 'chai'
import hre from 'hardhat'

describe('EpochManager configuration', () => {
  const {
    graphConfig,
    contracts: { EpochManager, Controller },
  } = hre.graph()

  it('should be controlled by Controller', async function () {
    const controller = await EpochManager.controller()
    expect(controller).eq(Controller.address)
  })

  it('epochLength should match "lengthInBlocks" in the config file', async function () {
    const value = await EpochManager.epochLength()
    const expected = getItemValue(graphConfig, 'contracts/EpochManager/init/lengthInBlocks')
    expect(value).eq(expected)
  })
})

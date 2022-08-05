import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../../../cli/config'
import { chainIdIsL2 } from '../../../../cli/utils'

describe('[L1] L1Reservoir configuration', () => {
  const {
    graphConfig,
    contracts: { Controller, L1Reservoir },
  } = hre.graph()

  before(async function () {
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    if (chainIdIsL2(chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await L1Reservoir.controller()
    expect(controller).eq(Controller.address)
  })

  it('dripInterval should match "dripInterval" in the config file', async function () {
    const value = await L1Reservoir.dripInterval()
    const expected = getItemValue(graphConfig, 'contracts/L1Reservoir/init/dripInterval')
    expect(value).eq(expected)
  })
})

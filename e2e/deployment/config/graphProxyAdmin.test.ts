import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../../cli/config'

describe('GraphProxyAdmin configuration', () => {
  const {
    contracts: { GraphProxyAdmin },
    graphConfig,
  } = hre.graph()

  it('should be owned by governor', async function () {
    const owner = await GraphProxyAdmin.governor()
    const governorAddress = getItemValue(graphConfig, 'general/governor')
    expect(owner).eq(governorAddress)
  })
})

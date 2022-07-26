import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../../cli/config'

describe('AllocationExchange configuration', () => {
  const {
    graphConfig,
    contracts: { AllocationExchange },
  } = hre.graph()

  it('should be owned by allocationExchangeOwner', async function () {
    const owner = await AllocationExchange.governor()
    const allocationExchangeOwner = getItemValue(graphConfig, 'general/allocationExchangeOwner')
    expect(owner).eq(allocationExchangeOwner)
  })

  it('should accept vouchers from authority', async function () {
    const authorityAddress = getItemValue(graphConfig, 'general/authority')
    const allowed = await AllocationExchange.authority(authorityAddress)
    expect(allowed).eq(true)
  })

  // graphToken and staking are private variables so we can't verify
  it.skip('graphToken should match the GraphToken deployment address')
  it.skip('staking should match the Staking deployment address')
})

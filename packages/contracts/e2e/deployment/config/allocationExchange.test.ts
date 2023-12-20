import { expect } from 'chai'
import hre from 'hardhat'
import { NamedAccounts } from '@graphprotocol/sdk/gre'

describe('AllocationExchange configuration', () => {
  const {
    contracts: { AllocationExchange },
    getNamedAccounts,
  } = hre.graph()

  let namedAccounts: NamedAccounts

  before(async () => {
    namedAccounts = await getNamedAccounts()
  })

  it('should be owned by allocationExchangeOwner', async function () {
    const owner = await AllocationExchange.governor()
    expect(owner).eq(namedAccounts.allocationExchangeOwner.address)
  })

  it('should accept vouchers from authority', async function () {
    const allowed = await AllocationExchange.authority(namedAccounts.authority.address)
    expect(allowed).eq(true)
  })

  // graphToken and staking are private variables so we can't verify
  it.skip('graphToken should match the GraphToken deployment address')
  it.skip('staking should match the Staking deployment address')
})

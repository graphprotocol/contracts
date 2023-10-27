import { expect } from 'chai'
import hre from 'hardhat'
import { NamedAccounts } from '@graphprotocol/sdk/gre'

describe('GraphProxyAdmin configuration', () => {
  const {
    contracts: { GraphProxyAdmin },
    getNamedAccounts,
  } = hre.graph()

  let namedAccounts: NamedAccounts

  before(async () => {
    namedAccounts = await getNamedAccounts()
  })

  it('should be owned by governor', async function () {
    const owner = await GraphProxyAdmin.governor()
    expect(owner).eq(namedAccounts.governor.address)
  })
})

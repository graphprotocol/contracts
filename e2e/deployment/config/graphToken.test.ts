import { expect } from 'chai'
import hre from 'hardhat'
import { NamedAccounts } from '@graphprotocol/sdk/gre'

describe('GraphToken configuration', () => {
  const {
    getNamedAccounts,
    contracts: { GraphToken },
    getDeployer,
  } = hre.graph()

  let namedAccounts: NamedAccounts

  before(async () => {
    namedAccounts = await getNamedAccounts()
  })

  it('should be owned by governor', async function () {
    const owner = await GraphToken.governor()
    expect(owner).eq(namedAccounts.governor.address)
  })

  it('deployer should not be minter', async function () {
    const deployer = await getDeployer()
    const deployerIsMinter = await GraphToken.isMinter(deployer.address)
    expect(deployerIsMinter).eq(false)
  })
})

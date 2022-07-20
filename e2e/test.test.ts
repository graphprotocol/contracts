import { expect } from 'chai'
import { getAccounts, Account, toGRT } from '../test/lib/testHelpers'
import hre from 'hardhat'

describe('Protocol deployment', () => {
  const { contracts } = hre.graph()
  const grt = contracts.GraphToken

  let deployer: Account

  before(async function () {
    ;[deployer] = await getAccounts()
  })

  it('Test GRT totalSupply', async function () {
    const totalSupply = await grt.totalSupply()
    expect(totalSupply).eq(toGRT('10000000000'))
  })

  it('Test deployer is not minter', async function () {
    const deployerIsMinter = await grt.isMinter(deployer.address)
    expect(deployerIsMinter).eq(false)
  })
})

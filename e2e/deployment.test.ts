import { expect } from 'chai'
import { ContractFactory } from 'ethers'
import { ethers } from 'hardhat'
import { getAccounts, Account, toGRT } from '../test/lib/testHelpers'
import { AddressBook, getAddressBook } from '../cli/address-book'
import { GraphToken } from '../build/types/GraphToken'

// Some ideas we could test
// Deployment:
// - Contract ownership of upgradeable contracts
// - Protocol parameters should match graph config file (init)
// - Protocol roles should be configured correctly
// Protocol:
// - traditional actions should work

describe('Protocol deployment', () => {
  const addressBook: AddressBook = getAddressBook('localhost.json', '1337')
  let deployer: Account
  let grtFactory: ContractFactory
  let grt: GraphToken

  before(async function () {
    ;[deployer] = await getAccounts()
    console.log(deployer.address)

    grtFactory = await ethers.getContractFactory('GraphToken', deployer)
    const contract = addressBook.getEntry('GraphToken')
    grt = grtFactory.attach(contract.address) as GraphToken
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

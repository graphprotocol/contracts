import { expect } from 'chai'
import hre, { ethers } from 'hardhat'
import { NamedAccounts } from '../../../gre/type-extensions'

describe('Controller configuration', () => {
  const { contracts, getNamedAccounts } = hre.graph()
  const { Controller } = contracts

  const proxyContracts = [
    'Curation',
    'GNS',
    'DisputeManager',
    'EpochManager',
    'RewardsManager',
    'Staking',
    'GraphToken',
  ]

  let namedAccounts: NamedAccounts

  before(async () => {
    namedAccounts = await getNamedAccounts()
  })

  const proxyShouldMatchDeployed = async (contractName: string) => {
    const curationAddress = await Controller.getContractProxy(
      ethers.utils.solidityKeccak256(['string'], [contractName]),
    )
    expect(curationAddress).eq(contracts[contractName].address)
  }

  it('should be owned by governor', async function () {
    const owner = await Controller.governor()
    expect(owner).eq(namedAccounts.governor.address)
  })

  it('pause guardian should be able to pause protocol', async function () {
    const pauseGuardian = await Controller.pauseGuardian()
    expect(pauseGuardian).eq(namedAccounts.pauseGuardian.address)
  })

  describe('proxy contract', async function () {
    for (const contract of proxyContracts) {
      it(`${contract} should match deployed`, async function () {
        await proxyShouldMatchDeployed(contract)
      })
    }
  })
})

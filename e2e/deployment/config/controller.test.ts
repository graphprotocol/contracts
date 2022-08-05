import { expect } from 'chai'
import hre, { ethers } from 'hardhat'
import { chainIdIsL2 } from '../../../cli/utils'
import { NamedAccounts } from '../../../tasks/type-extensions'

describe('Controller configuration', () => {
  const { contracts, getNamedAccounts } = hre.graph()
  const { Controller } = contracts

  const proxyContractsL1 = [
    'Curation',
    'GNS',
    'DisputeManager',
    'EpochManager',
    'RewardsManager',
    'Staking',
    'GraphToken',
    'L1GraphTokenGateway',
    'L1Reservoir',
  ]

  const proxyContractsL2 = [
    'Curation',
    'GNS',
    'DisputeManager',
    'EpochManager',
    'RewardsManager',
    'Staking',
    'L2GraphToken',
    'L2GraphTokenGateway',
    'L2Reservoir',
  ]

  let namedAccounts: NamedAccounts

  before(async () => {
    namedAccounts = await getNamedAccounts()
  })

  const proxyShouldMatchDeployed = async (contractName: string) => {
    // remove L1/L2 prefix, contracts are not registered as L1/L2 on controller
    const name = contractName.replace(/(^L1|L2)/gi, '')

    const address = await Controller.getContractProxy(
      ethers.utils.solidityKeccak256(['string'], [name]),
    )
    expect(address).eq(contracts[contractName].address)
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
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    const proxyContracts = chainIdIsL2(chainId) ? proxyContractsL2 : proxyContractsL1
    for (const contract of proxyContracts) {
      it(`${contract} should match deployed`, async function () {
        await proxyShouldMatchDeployed(contract)
      })
    }
  })
})

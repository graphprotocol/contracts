import { expect } from 'chai'
import hre, { ethers } from 'hardhat'
import { getItemValue } from '../../../cli/config'

describe('Controller configuration', () => {
  const { contracts, graphConfig } = hre.graph()
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

  const proxyShouldMatchDeployed = async (contractName: string) => {
    const curationAddress = await Controller.getContractProxy(
      ethers.utils.solidityKeccak256(['string'], [contractName]),
    )
    expect(curationAddress).eq(contracts[contractName].address)
  }

  it('should be owned by governor', async function () {
    const owner = await Controller.governor()
    const governorAddress = getItemValue(graphConfig, 'general/governor')
    expect(owner).eq(governorAddress)
  })

  it('pause guardian should be able to pause protocol', async function () {
    const pauseGuardianAddress = getItemValue(graphConfig, 'general/pauseGuardian')
    const pauseGuardian = await Controller.pauseGuardian()
    expect(pauseGuardian).eq(pauseGuardianAddress)
  })

  describe('proxy contract', async function () {
    for (const contract of proxyContracts) {
      it(`${contract} should match deployed`, async function () {
        await proxyShouldMatchDeployed(contract)
      })
    }
  })
})

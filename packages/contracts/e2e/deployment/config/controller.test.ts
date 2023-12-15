import { expect } from 'chai'
import hre, { ethers } from 'hardhat'
import { NamedAccounts } from '@graphprotocol/sdk/gre'
import { isGraphL1ChainId } from '@graphprotocol/sdk'

describe('Controller configuration', () => {
  const graph = hre.graph()
  const { Controller } = graph.contracts

  const l1ProxyContracts = [
    'Curation',
    'GNS',
    'DisputeManager',
    'EpochManager',
    'RewardsManager',
    'L1Staking',
    'GraphToken',
    'L1GraphTokenGateway',
  ]

  const l2ProxyContracts = [
    'Curation',
    'GNS',
    'DisputeManager',
    'EpochManager',
    'RewardsManager',
    'L2Staking',
    'L2GraphToken',
    'L2GraphTokenGateway',
  ]

  let namedAccounts: NamedAccounts

  before(async () => {
    namedAccounts = await graph.getNamedAccounts()
  })

  const proxyShouldMatchDeployed = async (contractName: string) => {
    // remove L1/L2 prefix, contracts are not registered as L1/L2 on controller
    const name = contractName.replace(/(^L1|L2)/gi, '')

    const address = await Controller.getContractProxy(
      ethers.utils.solidityKeccak256(['string'], [name]),
    )
    expect(address).eq(graph.contracts[contractName].address)
  }

  it('protocol should be unpaused', async function () {
    const paused = await Controller.paused()
    expect(paused).eq(false)
  })

  it('should be owned by governor', async function () {
    const owner = await Controller.governor()
    expect(owner).eq(namedAccounts.governor.address)
  })

  it('pause guardian should be able to pause protocol', async function () {
    const pauseGuardian = await Controller.pauseGuardian()
    expect(pauseGuardian).eq(namedAccounts.pauseGuardian.address)
  })

  describe('proxy contract', async function () {
    const proxyContracts = isGraphL1ChainId(graph.chainId) ? l1ProxyContracts : l2ProxyContracts
    for (const contract of proxyContracts) {
      it(`${contract} should match deployed`, async function () {
        await proxyShouldMatchDeployed(contract)
      })
    }
  })
})

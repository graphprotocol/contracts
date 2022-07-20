import { expect } from 'chai'
import hre from 'hardhat'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { getItem, getNode } from '../../cli/config'

describe('Contract ownership', () => {
  const { contracts, graphConfig } = hre.graph()

  const grt = contracts.GraphToken
  const controller = contracts.Controller
  const graphProxyAdmin = contracts.GraphProxyAdmin
  const subgraphNFT = contracts.SubgraphNFT
  const allocationExchange = contracts.AllocationExchange

  let deployer: SignerWithAddress
  const governorAddress = getItem(getNode(graphConfig, ['general']), 'governor').value
  const edgeAndNodeAddress = getItem(getNode(graphConfig, ['general']), 'edgeAndNode').value

  before(async function () {
    ;[deployer] = await hre.ethers.getSigners()
  })

  describe('deployer', () => {
    it('should not own GraphToken contract', async function () {
      const owner = await grt.governor()
      expect(owner).not.eq(deployer.address)
    })
    it('should not own Controller contract', async function () {
      const owner = await controller.governor()
      expect(owner).not.eq(deployer.address)
    })
    it('should not own GraphProxyAdmin contract', async function () {
      const owner = await graphProxyAdmin.governor()
      expect(owner).not.eq(deployer.address)
    })
    it('should not own SubgraphNFT contract', async function () {
      const owner = await subgraphNFT.governor()
      expect(owner).not.eq(deployer.address)
    })
    it('should not own AllocationExchange contract', async function () {
      const owner = await allocationExchange.governor()
      expect(owner).not.eq(deployer.address)
    })
  })

  describe('governor', () => {
    it('should own GraphToken contract', async function () {
      const owner = await grt.governor()
      expect(owner).eq(governorAddress)
    })
    it('should own Controller contract', async function () {
      const owner = await controller.governor()
      expect(owner).eq(governorAddress)
    })
    it('should own GraphProxyAdmin contract', async function () {
      const owner = await graphProxyAdmin.governor()
      expect(owner).eq(governorAddress)
    })
    it('should own SubgraphNFT contract', async function () {
      const owner = await subgraphNFT.governor()
      expect(owner).eq(governorAddress)
    })
  })

  describe('edge & node', () => {
    it('should own AllocationExchange contract', async function () {
      const owner = await allocationExchange.governor()
      expect(owner).eq(edgeAndNodeAddress)
    })
  })
})

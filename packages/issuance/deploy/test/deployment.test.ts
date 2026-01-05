import { expect } from 'chai'
import { ethers, deployments, getNamedAccounts } from 'hardhat'
import { Contract } from 'ethers'

describe('Issuance Deployment', function () {
  let deployer: string
  let governor: string

  before(async function () {
    const accounts = await getNamedAccounts()
    deployer = accounts.deployer
    governor = accounts.governor

    // Deploy all contracts with issuance tag
    await deployments.fixture(['issuance'])
  })

  describe('GraphIssuanceProxyAdmin', function () {
    let proxyAdmin: Contract

    beforeEach(async function () {
      const deployment = await deployments.get('GraphIssuanceProxyAdmin')
      proxyAdmin = await ethers.getContractAt('ProxyAdmin', deployment.address)
    })

    it('should be deployed', async function () {
      expect(await proxyAdmin.getAddress()).to.be.properAddress
    })

    it('should be owned by governor', async function () {
      const owner = await proxyAdmin.owner()
      expect(owner.toLowerCase()).to.equal(governor.toLowerCase())
    })
  })

  describe('IssuanceAllocator', function () {
    let issuanceAllocator: Contract
    let deployment: any

    beforeEach(async function () {
      deployment = await deployments.get('IssuanceAllocator')
      issuanceAllocator = await ethers.getContractAt('IssuanceAllocator', deployment.address)
    })

    it('should be deployed as proxy', async function () {
      expect(await issuanceAllocator.getAddress()).to.be.properAddress
      expect(deployment.implementation).to.be.properAddress
    })

    it('should have correct owner after acceptance', async function () {
      const owner = await issuanceAllocator.owner()
      // Governor should have accepted ownership via 04_accept_ownership
      expect(owner.toLowerCase()).to.equal(governor.toLowerCase())
    })

    it('should be initialized', async function () {
      // Try to initialize again - should revert
      await expect(
        issuanceAllocator.initialize(governor),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'InvalidInitialization')
    })

    it('should have GraphToken set', async function () {
      const graphToken = await deployments.get('GraphToken')
      const tokenAddress = await issuanceAllocator.graphToken()
      expect(tokenAddress.toLowerCase()).to.equal(graphToken.address.toLowerCase())
    })
  })

  describe('PilotAllocation', function () {
    let pilotAllocation: Contract
    let deployment: any

    beforeEach(async function () {
      deployment = await deployments.get('PilotAllocation')
      pilotAllocation = await ethers.getContractAt('DirectAllocation', deployment.address)
    })

    it('should be deployed as proxy', async function () {
      expect(await pilotAllocation.getAddress()).to.be.properAddress
      expect(deployment.implementation).to.be.properAddress
    })

    it('should have correct owner after acceptance', async function () {
      const owner = await pilotAllocation.owner()
      expect(owner.toLowerCase()).to.equal(governor.toLowerCase())
    })

    it('should be initialized', async function () {
      await expect(
        pilotAllocation.initialize(governor),
      ).to.be.revertedWithCustomError(pilotAllocation, 'InvalidInitialization')
    })

    it('should have GraphToken set', async function () {
      const graphToken = await deployments.get('GraphToken')
      const tokenAddress = await pilotAllocation.graphToken()
      expect(tokenAddress.toLowerCase()).to.equal(graphToken.address.toLowerCase())
    })
  })

  describe('RewardsEligibilityOracle', function () {
    let reo: Contract
    let deployment: any

    beforeEach(async function () {
      deployment = await deployments.get('RewardsEligibilityOracle')
      reo = await ethers.getContractAt('RewardsEligibilityOracle', deployment.address)
    })

    it('should be deployed as proxy', async function () {
      expect(await reo.getAddress()).to.be.properAddress
      expect(deployment.implementation).to.be.properAddress
    })

    it('should have correct owner after acceptance', async function () {
      const owner = await reo.owner()
      expect(owner.toLowerCase()).to.equal(governor.toLowerCase())
    })

    it('should be initialized', async function () {
      await expect(
        reo.initialize(governor),
      ).to.be.revertedWithCustomError(reo, 'InvalidInitialization')
    })

    it('should have GraphToken set', async function () {
      const graphToken = await deployments.get('GraphToken')
      const tokenAddress = await reo.graphToken()
      expect(tokenAddress.toLowerCase()).to.equal(graphToken.address.toLowerCase())
    })
  })

  describe('Proxy Architecture', function () {
    it('all proxies should use GraphIssuanceProxyAdmin', async function () {
      const proxyAdmin = await deployments.get('GraphIssuanceProxyAdmin')
      const contracts = ['IssuanceAllocator', 'PilotAllocation', 'RewardsEligibilityOracle']

      for (const contractName of contracts) {
        const deployment = await deployments.get(contractName)
        const proxy = await ethers.getContractAt('TransparentUpgradeableProxy', deployment.address)

        // ERC1967 admin slot
        const adminSlot = '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'
        const admin = await ethers.provider.getStorage(await proxy.getAddress(), adminSlot)
        const adminAddress = '0x' + admin.slice(26)

        expect(adminAddress.toLowerCase()).to.equal(proxyAdmin.address.toLowerCase())
      }
    })

    it('should have distinct implementation addresses', async function () {
      const iaImpl = (await deployments.get('IssuanceAllocator')).implementation
      const pilotImpl = (await deployments.get('PilotAllocation')).implementation
      const reoImpl = (await deployments.get('RewardsEligibilityOracle')).implementation

      expect(iaImpl).to.not.equal(pilotImpl)
      expect(iaImpl).to.not.equal(reoImpl)
      expect(pilotImpl).to.not.equal(reoImpl)
    })
  })

  describe('Address Book Export', function () {
    it('should export all required contracts', async function () {
      const requiredContracts = [
        'GraphIssuanceProxyAdmin',
        'IssuanceAllocator',
        'PilotAllocation',
        'RewardsEligibilityOracle',
      ]

      for (const contractName of requiredContracts) {
        const deployment = await deployments.getOrNull(contractName)
        expect(deployment).to.not.be.null
        expect(deployment?.address).to.be.properAddress
      }
    })
  })
})

import { expect } from 'chai'
import { Contract } from 'ethers'
import { artifacts, deployments, ethers, getNamedAccounts, network } from 'hardhat'

describe('Issuance Deployment', function () {
  let governor: string

  before(async function () {
    const accounts = await getNamedAccounts()
    governor = accounts.governor

    // Deploy all contracts with issuance tag
    await deployments.fixture(['issuance'])
  })

  describe('GraphIssuanceProxyAdmin', function () {
    let proxyAdmin: Contract

    beforeEach(async function () {
      const deployment = await deployments.get('GraphIssuanceProxyAdmin')
      // Use the deployment's ABI directly since ProxyAdmin is from OpenZeppelin
      proxyAdmin = new Contract(deployment.address, deployment.abi, ethers.provider as any)
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
      // Load the full contract artifact to get all functions including inherited ones
      const artifact = await artifacts.readArtifact('IssuanceAllocator')
      const [signer] = await ethers.getSigners()
      issuanceAllocator = new Contract(deployment.address, artifact.abi, signer as any)
    })

    it('should be deployed as proxy', async function () {
      expect(await issuanceAllocator.getAddress()).to.be.properAddress
      expect(deployment.implementation).to.be.properAddress
    })

    it('should have governor role assigned', async function () {
      // These contracts use role-based access control, not ownership
      const governorRole = await issuanceAllocator.GOVERNOR_ROLE()
      const hasGovernorRole = await issuanceAllocator.hasRole(governorRole, governor)
      expect(hasGovernorRole).to.be.true
    })

    it('should be initialized', async function () {
      // Try to initialize again - should revert
      await expect(issuanceAllocator.initialize(governor)).to.be.revertedWithCustomError(
        issuanceAllocator,
        'InvalidInitialization',
      )
    })
  })

  describe('PilotAllocation', function () {
    let pilotAllocation: Contract
    let deployment: any

    beforeEach(async function () {
      deployment = await deployments.get('PilotAllocation')
      // Load the full contract artifact to get all functions including inherited ones
      // Note: PilotAllocation deployment uses DirectAllocation contract
      const artifact = await artifacts.readArtifact('DirectAllocation')
      const [signer] = await ethers.getSigners()
      pilotAllocation = new Contract(deployment.address, artifact.abi, signer as any)
    })

    it('should be deployed as proxy', async function () {
      expect(await pilotAllocation.getAddress()).to.be.properAddress
      expect(deployment.implementation).to.be.properAddress
    })

    it('should have governor role assigned', async function () {
      // These contracts use role-based access control, not ownership
      const governorRole = await pilotAllocation.GOVERNOR_ROLE()
      const hasGovernorRole = await pilotAllocation.hasRole(governorRole, governor)
      expect(hasGovernorRole).to.be.true
    })

    it('should be initialized', async function () {
      await expect(pilotAllocation.initialize(governor)).to.be.revertedWithCustomError(
        pilotAllocation,
        'InvalidInitialization',
      )
    })
  })

  describe('RewardsEligibilityOracle', function () {
    let reo: Contract
    let deployment: any

    beforeEach(async function () {
      deployment = await deployments.get('RewardsEligibilityOracle')
      // Load the full contract artifact to get all functions including inherited ones
      const artifact = await artifacts.readArtifact('RewardsEligibilityOracle')
      const [signer] = await ethers.getSigners()
      reo = new Contract(deployment.address, artifact.abi, signer as any)
    })

    it('should be deployed as proxy', async function () {
      expect(await reo.getAddress()).to.be.properAddress
      expect(deployment.implementation).to.be.properAddress
    })

    it('should have governor role assigned', async function () {
      // These contracts use role-based access control, not ownership
      const governorRole = await reo.GOVERNOR_ROLE()
      const hasGovernorRole = await reo.hasRole(governorRole, governor)
      expect(hasGovernorRole).to.be.true
    })

    it('should be initialized', async function () {
      await expect(reo.initialize(governor)).to.be.revertedWithCustomError(reo, 'InvalidInitialization')
    })
  })

  describe('Proxy Architecture', function () {
    it('all proxies should use GraphIssuanceProxyAdmin', async function () {
      const proxyAdmin = await deployments.get('GraphIssuanceProxyAdmin')
      const contracts = ['IssuanceAllocator', 'PilotAllocation', 'RewardsEligibilityOracle']

      // ERC1967 admin slot: keccak256('eip1967.proxy.admin') - 1
      const adminSlot = '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'

      for (const contractName of contracts) {
        const deployment = await deployments.get(contractName)

        // Read admin from storage slot using raw JSON-RPC
        const admin = await network.provider.send('eth_getStorageAt', [deployment.address, adminSlot])
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

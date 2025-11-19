const { expect } = require('chai')
const { ethers, ignition } = require('hardhat')

describe('IssuanceAllocator Deployment', function () {
  let governor
  let mockGraphTokenAddress

  beforeEach(async function () {
    ;[, governor] = await ethers.getSigners()

    // Use a mock address for GraphToken (for testing deployment structure)
    mockGraphTokenAddress = '0x' + '1'.repeat(40)
  })

  describe('Complete System Deployment', function () {
    it('should deploy complete IssuanceAllocator system', async function () {
      // Import the deployment module
      const IssuanceAllocatorModule = require('../ignition/modules/IssuanceAllocator.ts').default

      // Deploy using Ignition
      const { proxyAdmin, issuanceAllocatorImpl, proxy } = await ignition.deploy(IssuanceAllocatorModule, {
        parameters: {
          IssuanceAllocator: {
            owner: governor.address,
            graphToken: mockGraphTokenAddress,
          },
        },
      })

      // Verify ProxyAdmin deployment
      expect(proxyAdmin.target).to.be.properAddress
      expect(await proxyAdmin.owner()).to.equal(governor.address)

      // Verify Implementation deployment
      expect(issuanceAllocatorImpl.target).to.be.properAddress
      // Note: graphToken is stored as immutable internal variable, not accessible externally

      // Verify Proxy deployment
      expect(proxy.target).to.be.properAddress

      // Verify proxy points to implementation
      const implementationSlot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
      const implementationAddress = await ethers.provider.getStorage(proxy.target, implementationSlot)
      const cleanImplementationAddress = ethers.getAddress('0x' + implementationAddress.slice(-40))
      expect(cleanImplementationAddress).to.equal(issuanceAllocatorImpl.target)
    })

    it('should initialize proxy correctly', async function () {
      const IssuanceAllocatorModule = require('../ignition/modules/IssuanceAllocator.ts').default

      const { proxy } = await ignition.deploy(IssuanceAllocatorModule, {
        parameters: {
          IssuanceAllocator: {
            owner: governor.address,
            graphToken: mockGraphTokenAddress,
          },
        },
      })

      // Create interface to interact with proxy as IssuanceAllocator
      const IssuanceAllocator = await ethers.getContractFactory('IssuanceAllocator')
      const issuanceAllocator = IssuanceAllocator.attach(proxy.target)

      // Verify initialization - check if governor role is set
      expect(await issuanceAllocator.hasRole(await issuanceAllocator.GOVERNOR_ROLE(), governor.address)).to.be.true
      // Note: graphToken is stored as immutable internal variable, not accessible externally
    })

    it('should have correct contract interfaces', async function () {
      const IssuanceAllocatorModule = require('../ignition/modules/IssuanceAllocator.ts').default

      const { issuanceAllocatorImpl } = await ignition.deploy(IssuanceAllocatorModule, {
        parameters: {
          IssuanceAllocator: {
            owner: governor.address,
            graphToken: mockGraphTokenAddress,
          },
        },
      })

      // Check key functions exist
      expect(issuanceAllocatorImpl.interface.getFunction('initialize')).to.exist
      expect(issuanceAllocatorImpl.interface.getFunction('distributeIssuance')).to.exist
      expect(issuanceAllocatorImpl.interface.getFunction('issuancePerBlock')).to.exist
    })
  })
})

import { expect } from 'chai'
import { ethers, ignition } from 'hardhat'

import IssuanceAllocatorModule from '../ignition/modules/IssuanceAllocator'

describe('IssuanceAllocator Deployment', function () {
  let governor: any
  let mockGraphTokenAddress: string

  beforeEach(async function () {
    ;[, governor] = await ethers.getSigners()

    // Use a mock address for GraphToken (for testing deployment structure)
    mockGraphTokenAddress = '0x' + '1'.repeat(40)
  })

  describe('Complete System Deployment', function () {
    it('should deploy complete IssuanceAllocator system', async function () {
      // Deploy using Ignition
      const { IssuanceAllocatorProxyAdmin, IssuanceAllocatorImplementation, IssuanceAllocator } = await ignition.deploy(
        IssuanceAllocatorModule,
        {
          parameters: {
            IssuanceAllocator: {
              graphTokenAddress: mockGraphTokenAddress,
            },
          },
          defaultSender: governor.address,
        },
      )

      // Verify ProxyAdmin deployment
      expect(IssuanceAllocatorProxyAdmin.target).to.be.properAddress
      expect(await IssuanceAllocatorProxyAdmin.owner()).to.equal(governor.address)

      // Verify Implementation deployment
      expect(IssuanceAllocatorImplementation.target).to.be.properAddress
      // Note: graphToken is stored as immutable internal variable, not accessible externally

      // Verify Proxy deployment
      expect(IssuanceAllocator.target).to.be.properAddress

      // Verify proxy points to implementation
      const implementationSlot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
      const implementationAddress = await ethers.provider.getStorage(IssuanceAllocator.target, implementationSlot)
      const cleanImplementationAddress = ethers.getAddress('0x' + implementationAddress.slice(-40))
      expect(cleanImplementationAddress).to.equal(IssuanceAllocatorImplementation.target)
    })

    it('should initialize proxy correctly', async function () {
      const { IssuanceAllocator } = await ignition.deploy(IssuanceAllocatorModule, {
        parameters: {
          IssuanceAllocator: {
            graphTokenAddress: mockGraphTokenAddress,
          },
        },
        defaultSender: governor.address,
      })

      // Create interface to interact with proxy as IssuanceAllocator
      const IssuanceAllocatorFactory = await ethers.getContractFactory('IssuanceAllocator')
      const issuanceAllocator = IssuanceAllocatorFactory.attach(IssuanceAllocator.target)

      // Verify initialization - check if governor role is set
      expect(await issuanceAllocator.hasRole(await issuanceAllocator.GOVERNOR_ROLE(), governor.address)).to.be.true
      // Note: graphToken is stored as immutable internal variable, not accessible externally
    })

    it('should have correct contract interfaces', async function () {
      const { IssuanceAllocatorImplementation } = await ignition.deploy(IssuanceAllocatorModule, {
        parameters: {
          IssuanceAllocator: {
            graphTokenAddress: mockGraphTokenAddress,
          },
        },
        defaultSender: governor.address,
      })

      // Check key functions exist
      expect(IssuanceAllocatorImplementation.interface.getFunction('initialize')).to.exist
      expect(IssuanceAllocatorImplementation.interface.getFunction('distributeIssuance')).to.exist
      expect(IssuanceAllocatorImplementation.interface.getFunction('issuancePerBlock')).to.exist
    })
  })
})

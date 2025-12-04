import { expect } from 'chai'
import { ethers, ignition } from 'hardhat'

import IssuanceAllocatorModule from '../../issuance/deploy/ignition/modules/IssuanceAllocator'
import GraphIssuanceProxyAdminModule from '../../issuance/deploy/ignition/modules/GraphIssuanceProxyAdmin'
import IssuanceAllocatorArtifact from '../../issuance/artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json'
import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'

/**
 * Test suite demonstrating the governed deployment pattern for issuance contracts
 *
 * This shows the complete flow:
 * 1. Deploy ProxyAdmin, Implementation, and Proxy via Ignition
 * 2. Initialize contract via governance transaction (ProxyAdmin.upgradeAndCall)
 * 3. Verify initialization succeeded
 * 4. Upgrade flow: deploy new implementation + upgradeAndCall
 */
describe('Issuance Governed Deployment Pattern', function () {
  let deployer: any
  let governor: any
  let mockGraphTokenAddress: string

  beforeEach(async function () {
    ;[deployer, governor] = await ethers.getSigners()
    mockGraphTokenAddress = '0x' + '1'.repeat(40)
  })

  describe('Initial Deployment with Atomic Initialization', function () {
    it('should deploy system with atomic initialization (prevents front-running)', async function () {
      // STEP 1: Deploy using Ignition (deployer account)
      // This deploys: GraphIssuanceProxyAdmin → Implementation → TransparentUpgradeableProxy
      // SECURITY: Proxy is initialized atomically during deployment via constructor calldata
      const { IssuanceAllocator, IssuanceAllocatorImplementation } = await ignition.deploy(
        IssuanceAllocatorModule,
        {
          parameters: {
            IssuanceAllocator: {
              graphTokenAddress: mockGraphTokenAddress,
            },
          },
          defaultSender: deployer.address,
        },
      )

      // Deploy GraphIssuanceProxyAdmin separately to get reference
      const { GraphIssuanceProxyAdmin } = await ignition.deploy(GraphIssuanceProxyAdminModule, {
        defaultSender: deployer.address,
      })

      // Verify deployments
      expect(IssuanceAllocator.target).to.be.properAddress
      expect(IssuanceAllocatorImplementation.target).to.be.properAddress
      expect(GraphIssuanceProxyAdmin.target).to.be.properAddress

      // Verify ProxyAdmin is owned by governor (set in constructor)
      expect(await GraphIssuanceProxyAdmin.owner()).to.equal(governor.address)

      // STEP 2: Verify atomic initialization succeeded
      // The proxy was initialized during deployment - no separate transaction needed
      const IssuanceAllocatorFactory = await ethers.getContractFactoryFromArtifact(IssuanceAllocatorArtifact)
      const issuanceAllocator = IssuanceAllocatorFactory.attach(IssuanceAllocator.target)

      // Verify governor role was set during deployment
      expect(await issuanceAllocator.hasRole(await issuanceAllocator.GOVERNOR_ROLE(), governor.address)).to.be.true

      // Verify proxy points to implementation
      const implementationSlot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
      const implementationAddress = await ethers.provider.getStorage(IssuanceAllocator.target, implementationSlot)
      const cleanImplementationAddress = ethers.getAddress('0x' + implementationAddress.slice(-40))
      expect(cleanImplementationAddress).to.equal(IssuanceAllocatorImplementation.target)
    })
  })

  describe('Governance and Security', function () {
    it('should have ProxyAdmin owned by governor', async function () {
      const { GraphIssuanceProxyAdmin } = await ignition.deploy(GraphIssuanceProxyAdminModule, {
        defaultSender: deployer.address,
      })

      // Create ProxyAdmin contract instance
      const ProxyAdminFactory = await ethers.getContractFactoryFromArtifact(ProxyAdminArtifact)
      const proxyAdmin = ProxyAdminFactory.attach(GraphIssuanceProxyAdmin.target)

      // Verify ProxyAdmin is owned by governor
      expect(await proxyAdmin.owner()).to.equal(governor.address)
    })

    it('should prevent double initialization', async function () {
      const { IssuanceAllocator } = await ignition.deploy(IssuanceAllocatorModule, {
        parameters: {
          IssuanceAllocator: {
            graphTokenAddress: mockGraphTokenAddress,
          },
        },
        defaultSender: deployer.address,
      })

      // Get contract instance
      const IssuanceAllocatorFactory = await ethers.getContractFactoryFromArtifact(IssuanceAllocatorArtifact)
      const issuanceAllocator = IssuanceAllocatorFactory.attach(IssuanceAllocator.target)

      // Verify contract is already initialized (governor role is set)
      expect(await issuanceAllocator.hasRole(await issuanceAllocator.GOVERNOR_ROLE(), governor.address)).to.be.true

      // Attempt to initialize again should fail
      await expect(issuanceAllocator.connect(governor).initialize(governor.address)).to.be.revertedWithCustomError(
        issuanceAllocator,
        'InvalidInitialization',
      )
    })

    it('should prevent unauthorized access to ProxyAdmin functions', async function () {
      const { IssuanceAllocator } = await ignition.deploy(IssuanceAllocatorModule, {
        parameters: {
          IssuanceAllocator: {
            graphTokenAddress: mockGraphTokenAddress,
          },
        },
        defaultSender: deployer.address,
      })

      const { GraphIssuanceProxyAdmin } = await ignition.deploy(GraphIssuanceProxyAdminModule, {
        defaultSender: deployer.address,
      })

      // Create ProxyAdmin contract instance
      const ProxyAdminFactory = await ethers.getContractFactoryFromArtifact(ProxyAdminArtifact)
      const proxyAdmin = ProxyAdminFactory.attach(GraphIssuanceProxyAdmin.target)

      // Deploy a mock implementation
      const newImplementationFactory = await ethers.getContractFactoryFromArtifact(IssuanceAllocatorArtifact)
      const newImplementation = await newImplementationFactory.deploy(mockGraphTokenAddress)
      await newImplementation.waitForDeployment()

      // Verify non-governor cannot upgrade
      await expect(
        proxyAdmin.connect(deployer).upgradeAndCall(IssuanceAllocator.target, newImplementation.target, '0x'),
      ).to.be.revertedWithCustomError(proxyAdmin, 'OwnableUnauthorizedAccount')
    })
  })

  describe('Module Structure', function () {
    it('should deploy all components via single module', async function () {
      const deployment = await ignition.deploy(IssuanceAllocatorModule, {
        parameters: {
          IssuanceAllocator: {
            graphTokenAddress: mockGraphTokenAddress,
          },
        },
        defaultSender: deployer.address,
      })

      // Verify all components are deployed
      expect(deployment.IssuanceAllocator).to.exist
      expect(deployment.IssuanceAllocatorImplementation).to.exist

      // Verify types
      expect(deployment.IssuanceAllocator.target).to.be.properAddress
      expect(deployment.IssuanceAllocatorImplementation.target).to.be.properAddress

      // Verify they're different addresses
      expect(deployment.IssuanceAllocator.target).to.not.equal(
        deployment.IssuanceAllocatorImplementation.target,
      )
    })
  })
})

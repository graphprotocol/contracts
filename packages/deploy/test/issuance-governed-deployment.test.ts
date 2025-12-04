import { expect } from 'chai'
import { ethers, ignition } from 'hardhat'

import IssuanceAllocatorModule from '../../issuance/deploy/ignition/modules/IssuanceAllocator'
import GraphIssuanceProxyAdminModule from '../../issuance/deploy/ignition/modules/GraphIssuanceProxyAdmin'
import IssuanceAllocatorArtifact from '../../issuance/artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json'

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

  describe('Initial Deployment + Governed Initialization', function () {
    it('should deploy system and initialize via governance transaction', async function () {
      // STEP 1: Deploy using Ignition (deployer account)
      // This deploys: GraphIssuanceProxyAdmin → Implementation → TransparentUpgradeableProxy
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

      // STEP 2: Prepare initialization call data
      const IssuanceAllocatorFactory = await ethers.getContractFactoryFromArtifact(IssuanceAllocatorArtifact)
      const issuanceAllocator = IssuanceAllocatorFactory.attach(IssuanceAllocator.target)

      const initializeData = issuanceAllocator.interface.encodeFunctionData('initialize', [governor.address])

      // STEP 3: Governor executes upgradeAndCall to initialize
      // This is the governed initialization pattern - even initial setup uses governance transaction
      await GraphIssuanceProxyAdmin.connect(governor).upgradeAndCall(
        IssuanceAllocator.target,
        IssuanceAllocatorImplementation.target,
        initializeData,
      )

      // STEP 4: Verify initialization succeeded
      expect(await issuanceAllocator.hasRole(await issuanceAllocator.GOVERNOR_ROLE(), governor.address)).to.be.true

      // Verify proxy points to implementation
      const implementationSlot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
      const implementationAddress = await ethers.provider.getStorage(IssuanceAllocator.target, implementationSlot)
      const cleanImplementationAddress = ethers.getAddress('0x' + implementationAddress.slice(-40))
      expect(cleanImplementationAddress).to.equal(IssuanceAllocatorImplementation.target)
    })
  })

  describe('Upgrade Flow via Governance', function () {
    it('should upgrade implementation via governance transaction', async function () {
      // STEP 1: Deploy initial system
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

      const { GraphIssuanceProxyAdmin } = await ignition.deploy(GraphIssuanceProxyAdminModule, {
        defaultSender: deployer.address,
      })

      // ProxyAdmin is already owned by governor (from constructor)
      // Initialize via governance
      const IssuanceAllocatorFactory = await ethers.getContractFactoryFromArtifact(IssuanceAllocatorArtifact)
      const issuanceAllocator = IssuanceAllocatorFactory.attach(IssuanceAllocator.target)

      const initializeData = issuanceAllocator.interface.encodeFunctionData('initialize', [governor.address])
      await GraphIssuanceProxyAdmin.connect(governor).upgradeAndCall(
        IssuanceAllocator.target,
        IssuanceAllocatorImplementation.target,
        initializeData,
      )

      const initialImplementation = IssuanceAllocatorImplementation.target

      // STEP 2: Simulate deployment of new implementation
      // In practice, this would be a new Ignition run with updated contract code
      // For this test, we'll verify the upgrade mechanism works

      // Query current implementation via ProxyAdmin
      const currentImpl = await GraphIssuanceProxyAdmin.connect(governor).getProxyImplementation(
        IssuanceAllocator.target,
      )
      expect(currentImpl).to.equal(initialImplementation)

      // STEP 3: Governor executes upgradeAndCall with new implementation
      // (In this test, we "upgrade" to the same implementation to verify the mechanism)
      // In production, this would be a different implementation address
      await GraphIssuanceProxyAdmin.connect(governor).upgradeAndCall(
        IssuanceAllocator.target,
        IssuanceAllocatorImplementation.target,
        '0x', // No re-initialization needed for upgrades
      )

      // STEP 4: Verify upgrade succeeded
      const newImpl = await GraphIssuanceProxyAdmin.connect(governor).getProxyImplementation(
        IssuanceAllocator.target,
      )
      expect(newImpl).to.equal(IssuanceAllocatorImplementation.target)

      // Verify proxy state persisted through upgrade
      expect(await issuanceAllocator.hasRole(await issuanceAllocator.GOVERNOR_ROLE(), governor.address)).to.be.true
    })

    it('should enforce governance-only access to upgrade functions', async function () {
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

      const { GraphIssuanceProxyAdmin } = await ignition.deploy(GraphIssuanceProxyAdminModule, {
        defaultSender: deployer.address,
      })

      // ProxyAdmin is already owned by governor (from constructor)

      // Verify non-governor cannot upgrade
      await expect(
        GraphIssuanceProxyAdmin.connect(deployer).upgradeAndCall(
          IssuanceAllocator.target,
          IssuanceAllocatorImplementation.target,
          '0x',
        ),
      ).to.be.revertedWithCustomError(GraphIssuanceProxyAdmin, 'OwnableUnauthorizedAccount')

      // Verify governor can upgrade
      await expect(
        GraphIssuanceProxyAdmin.connect(governor).upgradeAndCall(
          IssuanceAllocator.target,
          IssuanceAllocatorImplementation.target,
          '0x',
        ),
      ).to.not.be.reverted
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

import { RewardsManager } from '@graphprotocol/contracts'
import { GraphNetworkContracts, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { constants } from 'ethers'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

describe('Rewards - Issuance Allocator', () => {
  const graph = hre.graph()
  let governor: SignerWithAddress
  let indexer1: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let rewardsManager: RewardsManager

  const ISSUANCE_PER_BLOCK = toGRT('200') // 200 GRT every block

  before(async function () {
    const testAccounts = await graph.getTestAccounts()
    indexer1 = testAccounts[0]
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    rewardsManager = contracts.RewardsManager as RewardsManager

    // 200 GRT per block
    await rewardsManager.connect(governor).setIssuancePerBlock(ISSUANCE_PER_BLOCK)
  })

  beforeEach(async function () {
    await fixture.setUp()
    // Reset issuance allocator to ensure we use direct issuancePerBlock
    await rewardsManager.connect(governor).setIssuanceAllocator(constants.AddressZero)
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('setIssuanceAllocator', function () {
    describe('ERC-165 validation', function () {
      it('should successfully set an issuance allocator that supports the interface', async function () {
        // Deploy a mock issuance allocator that supports ERC-165 and IIssuanceAllocationDistribution
        const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
        )
        const mockAllocator = await MockIssuanceAllocatorFactory.deploy(hre.ethers.utils.parseEther('50'))
        await mockAllocator.deployed()

        // Should succeed because MockIssuanceAllocator supports IIssuanceAllocationDistribution
        await expect(rewardsManager.connect(governor).setIssuanceAllocator(mockAllocator.address))
          .to.emit(rewardsManager, 'IssuanceAllocatorSet')
          .withArgs(constants.AddressZero, mockAllocator.address)

        // Verify the allocator was set
        expect(await rewardsManager.issuanceAllocator()).to.equal(mockAllocator.address)
      })

      it('should revert when setting to EOA address (no contract code)', async function () {
        const eoaAddress = indexer1.address

        // Should revert because EOAs don't have contract code to call supportsInterface on
        await expect(rewardsManager.connect(governor).setIssuanceAllocator(eoaAddress)).to.be.reverted
      })

      it('should revert when setting to contract that does not support IIssuanceAllocationDistribution', async function () {
        // Deploy a contract that supports ERC-165 but not IIssuanceAllocationDistribution
        const MockERC165OnlyFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockERC165OnlyContract.sol:MockERC165OnlyContract',
        )
        const erc165OnlyContract = await MockERC165OnlyFactory.deploy()
        await erc165OnlyContract.deployed()

        // Should revert because the contract doesn't support IIssuanceAllocationDistribution
        await expect(
          rewardsManager.connect(governor).setIssuanceAllocator(erc165OnlyContract.address),
        ).to.be.revertedWith('Contract does not support IIssuanceAllocationDistribution interface')
      })

      it('should validate interface before updating rewards calculation', async function () {
        // This test ensures that ERC165 validation happens before updateAccRewardsPerSignal
        // Deploy a contract that doesn't support IIssuanceAllocationDistribution
        const MockERC165OnlyFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockERC165OnlyContract.sol:MockERC165OnlyContract',
        )
        const erc165OnlyContract = await MockERC165OnlyFactory.deploy()
        await erc165OnlyContract.deployed()

        // Should revert with interface error, not with any rewards calculation error
        await expect(
          rewardsManager.connect(governor).setIssuanceAllocator(erc165OnlyContract.address),
        ).to.be.revertedWith('Contract does not support IIssuanceAllocationDistribution interface')
      })
    })

    describe('access control', function () {
      it('should revert when called by non-governor', async function () {
        const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
        )
        const mockAllocator = await MockIssuanceAllocatorFactory.deploy(toGRT('50'))
        await mockAllocator.deployed()

        // Should revert because indexer1 is not the governor
        await expect(rewardsManager.connect(indexer1).setIssuanceAllocator(mockAllocator.address)).to.be.revertedWith(
          'Only Controller governor',
        )
      })
    })

    describe('state management', function () {
      it('should allow setting issuance allocator to zero address (disable)', async function () {
        // First set a valid allocator
        const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
        )
        const mockAllocator = await MockIssuanceAllocatorFactory.deploy(toGRT('50'))
        await mockAllocator.deployed()

        await rewardsManager.connect(governor).setIssuanceAllocator(mockAllocator.address)
        expect(await rewardsManager.issuanceAllocator()).to.equal(mockAllocator.address)

        // Now disable by setting to zero address
        await expect(rewardsManager.connect(governor).setIssuanceAllocator(constants.AddressZero))
          .to.emit(rewardsManager, 'IssuanceAllocatorSet')
          .withArgs(mockAllocator.address, constants.AddressZero)

        expect(await rewardsManager.issuanceAllocator()).to.equal(constants.AddressZero)

        // Should now use local issuancePerBlock again
        expect(await rewardsManager.getRewardsIssuancePerBlock()).eq(ISSUANCE_PER_BLOCK)
      })

      it('should emit IssuanceAllocatorSet event when setting allocator', async function () {
        const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
        )
        const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy(toGRT('50'))
        await mockIssuanceAllocator.deployed()

        const tx = rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)
        await expect(tx)
          .emit(rewardsManager, 'IssuanceAllocatorSet')
          .withArgs(constants.AddressZero, mockIssuanceAllocator.address)
      })

      it('should not emit event when setting to same allocator address', async function () {
        // Deploy a mock issuance allocator
        const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
        )
        const mockAllocator = await MockIssuanceAllocatorFactory.deploy(toGRT('50'))
        await mockAllocator.deployed()

        // Set the allocator first time
        await rewardsManager.connect(governor).setIssuanceAllocator(mockAllocator.address)

        // Setting to same address should not emit event
        const tx = await rewardsManager.connect(governor).setIssuanceAllocator(mockAllocator.address)
        const receipt = await tx.wait()

        // Filter for IssuanceAllocatorSet events
        const events = receipt.events?.filter((e) => e.event === 'IssuanceAllocatorSet') || []
        expect(events.length).to.equal(0)
      })

      it('should update rewards before changing issuance allocator', async function () {
        // This test verifies that updateAccRewardsPerSignal is called when setting allocator
        const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
        )
        const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy(toGRT('50'))
        await mockIssuanceAllocator.deployed()

        // Setting the allocator should trigger updateAccRewardsPerSignal
        // We can't easily test this directly, but we can verify the allocator was set
        await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)
        expect(await rewardsManager.issuanceAllocator()).eq(mockIssuanceAllocator.address)
      })
    })
  })

  describe('getRewardsIssuancePerBlock', function () {
    it('should return issuancePerBlock when no issuanceAllocator is set', async function () {
      const expectedIssuance = toGRT('100.025')
      await rewardsManager.connect(governor).setIssuancePerBlock(expectedIssuance)

      // Ensure no issuanceAllocator is set
      expect(await rewardsManager.issuanceAllocator()).eq(constants.AddressZero)

      // Should return the direct issuancePerBlock value
      expect(await rewardsManager.getRewardsIssuancePerBlock()).eq(expectedIssuance)
    })

    it('should return value from issuanceAllocator when set', async function () {
      // Create a mock IssuanceAllocator with initial rate
      const initialRate = toGRT('50')
      const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy(initialRate)
      await mockIssuanceAllocator.deployed()

      // Set the mock allocator on RewardsManager
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      // Verify the allocator was set
      expect(await rewardsManager.issuanceAllocator()).eq(mockIssuanceAllocator.address)

      // Register RewardsManager as a self-minting target with allocation
      const allocation = 500000 // 50% in PPM (parts per million)
      await mockIssuanceAllocator['setTargetAllocation(address,uint256,uint256,bool)'](
        rewardsManager.address,
        0,
        allocation,
        true,
      )

      // Expected issuance should be (initialRate * allocation) / 1000000
      const expectedIssuance = initialRate.mul(allocation).div(1000000)

      // Should return the value from the allocator, not the local issuancePerBlock
      expect(await rewardsManager.getRewardsIssuancePerBlock()).eq(expectedIssuance)
    })

    it('should return 0 when issuanceAllocator is set but target not registered as self-minter', async function () {
      // Create a mock IssuanceAllocator
      const initialRate = toGRT('50')
      const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy(initialRate)
      await mockIssuanceAllocator.deployed()

      // Set the mock allocator on RewardsManager
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      // Register RewardsManager as a NON-self-minting target
      const allocation = 500000 // 50% in PPM
      await mockIssuanceAllocator['setTargetAllocation(address,uint256,uint256,bool)'](
        rewardsManager.address,
        allocation,
        0,
        false,
      ) // selfMinter = false

      // Should return 0 because it's not a self-minting target
      expect(await rewardsManager.getRewardsIssuancePerBlock()).eq(0)
    })
  })

  describe('setIssuancePerBlock', function () {
    it('should allow setIssuancePerBlock when issuanceAllocator is set', async function () {
      // Create and set a mock IssuanceAllocator
      const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy(toGRT('50'))
      await mockIssuanceAllocator.deployed()
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      // Should allow setting issuancePerBlock even when allocator is set
      const newIssuancePerBlock = toGRT('100')
      await rewardsManager.connect(governor).setIssuancePerBlock(newIssuancePerBlock)

      // The local issuancePerBlock should be updated
      expect(await rewardsManager.issuancePerBlock()).eq(newIssuancePerBlock)

      // But the effective issuance should still come from the allocator
      // (assuming the allocator returns a different value)
      expect(await rewardsManager.getRewardsIssuancePerBlock()).not.eq(newIssuancePerBlock)
    })
  })

  describe('beforeIssuanceAllocationChange', function () {
    it('should handle beforeIssuanceAllocationChange correctly', async function () {
      // Create and set a mock IssuanceAllocator
      const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy(toGRT('50'))
      await mockIssuanceAllocator.deployed()
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      // Anyone should be able to call this function
      await rewardsManager.connect(governor).beforeIssuanceAllocationChange()

      // Should also succeed when called by the allocator
      await mockIssuanceAllocator.callBeforeIssuanceAllocationChange(rewardsManager.address)
    })
  })
})

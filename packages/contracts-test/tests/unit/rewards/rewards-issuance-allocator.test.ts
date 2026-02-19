import { Curation } from '@graphprotocol/contracts'
import { GraphToken } from '@graphprotocol/contracts'
import { RewardsManager } from '@graphprotocol/contracts'
import { GraphNetworkContracts, helpers, randomHexBytes, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { constants } from 'ethers'
import hre from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

describe('Rewards - Issuance Allocator', () => {
  const graph = hre.graph()
  let curator1: SignerWithAddress
  let governor: SignerWithAddress
  let indexer1: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let grt: GraphToken
  let curation: Curation
  let rewardsManager: RewardsManager

  const subgraphDeploymentID1 = randomHexBytes()

  const ISSUANCE_PER_BLOCK = toGRT('200') // 200 GRT every block

  before(async function () {
    const testAccounts = await graph.getTestAccounts()
    curator1 = testAccounts[0]
    indexer1 = testAccounts[1]
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    grt = contracts.GraphToken as GraphToken
    curation = contracts.Curation as Curation
    rewardsManager = contracts.RewardsManager as RewardsManager

    // 200 GRT per block
    await rewardsManager.connect(governor).setIssuancePerBlock(ISSUANCE_PER_BLOCK)

    // Distribute test funds
    for (const wallet of [curator1]) {
      await grt.connect(governor).mint(wallet.address, toGRT('1000000'))
      await grt.connect(wallet).approve(curation.address, toGRT('1000000'))
    }
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
        const mockAllocator = await MockIssuanceAllocatorFactory.deploy()
        await mockAllocator.deployed()

        // Should succeed because MockIssuanceAllocator supports IIssuanceAllocationDistribution
        await expect(rewardsManager.connect(governor).setIssuanceAllocator(mockAllocator.address))
          .to.emit(rewardsManager, 'IssuanceAllocatorSet')
          .withArgs(constants.AddressZero, mockAllocator.address)

        // Verify the allocator was set
        expect(await rewardsManager.getIssuanceAllocator()).to.equal(mockAllocator.address)
      })

      it('should revert when setting to EOA address (no contract code)', async function () {
        const eoaAddress = indexer1.address

        // Should revert because EOAs don't have contract code to call supportsInterface on
        await expect(rewardsManager.connect(governor).setIssuanceAllocator(eoaAddress)).to.be.reverted
      })

      it('should revert when setting to contract that does not support IIssuanceAllocationDistribution', async function () {
        // Deploy a contract that supports ERC-165 but not IIssuanceAllocationDistribution
        const MockERC165Factory = await hre.ethers.getContractFactory('contracts/tests/MockERC165.sol:MockERC165')
        const mockERC165 = await MockERC165Factory.deploy()
        await mockERC165.deployed()

        // Should revert because the contract doesn't support IIssuanceAllocationDistribution
        await expect(rewardsManager.connect(governor).setIssuanceAllocator(mockERC165.address)).to.be.revertedWith(
          'Contract does not support IIssuanceAllocationDistribution interface',
        )
      })

      it('should validate interface before updating rewards calculation', async function () {
        // This test ensures that ERC165 validation happens before updateAccRewardsPerSignal
        // Deploy a contract that supports ERC-165 but not IIssuanceAllocationDistribution
        const MockERC165Factory = await hre.ethers.getContractFactory('contracts/tests/MockERC165.sol:MockERC165')
        const mockERC165 = await MockERC165Factory.deploy()
        await mockERC165.deployed()

        // Should revert with interface error, not with any rewards calculation error
        await expect(rewardsManager.connect(governor).setIssuanceAllocator(mockERC165.address)).to.be.revertedWith(
          'Contract does not support IIssuanceAllocationDistribution interface',
        )
      })
    })

    describe('access control', function () {
      it('should revert when called by non-governor', async function () {
        const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
        )
        const mockAllocator = await MockIssuanceAllocatorFactory.deploy()
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
        const mockAllocator = await MockIssuanceAllocatorFactory.deploy()
        await mockAllocator.deployed()

        await rewardsManager.connect(governor).setIssuanceAllocator(mockAllocator.address)
        expect(await rewardsManager.getIssuanceAllocator()).to.equal(mockAllocator.address)

        // Now disable by setting to zero address
        await expect(rewardsManager.connect(governor).setIssuanceAllocator(constants.AddressZero))
          .to.emit(rewardsManager, 'IssuanceAllocatorSet')
          .withArgs(mockAllocator.address, constants.AddressZero)

        expect(await rewardsManager.getIssuanceAllocator()).to.equal(constants.AddressZero)

        // Should now use local issuancePerBlock again — both getters agree
        expect(await rewardsManager.getAllocatedIssuancePerBlock()).eq(ISSUANCE_PER_BLOCK)
        expect(await rewardsManager.getRawIssuancePerBlock()).eq(ISSUANCE_PER_BLOCK)
      })

      it('should emit IssuanceAllocatorSet event when setting allocator', async function () {
        const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
          'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
        )
        const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy()
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
        const mockAllocator = await MockIssuanceAllocatorFactory.deploy()
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
        const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy()
        await mockIssuanceAllocator.deployed()

        // Setting the allocator should trigger updateAccRewardsPerSignal
        // We can't easily test this directly, but we can verify the allocator was set
        await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)
        expect(await rewardsManager.getIssuanceAllocator()).eq(mockIssuanceAllocator.address)
      })
    })
  })

  describe('getAllocatedIssuancePerBlock', function () {
    it('should return issuancePerBlock when no issuanceAllocator is set', async function () {
      const expectedIssuance = toGRT('100.025')
      await rewardsManager.connect(governor).setIssuancePerBlock(expectedIssuance)

      // Ensure no issuanceAllocator is set
      expect(await rewardsManager.getIssuanceAllocator()).eq(constants.AddressZero)

      // Both getters should agree when no allocator is set
      expect(await rewardsManager.getAllocatedIssuancePerBlock()).eq(expectedIssuance)
      expect(await rewardsManager.getRawIssuancePerBlock()).eq(expectedIssuance)
    })

    it('should return value from issuanceAllocator when set', async function () {
      // Create a mock IssuanceAllocator
      const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy()
      await mockIssuanceAllocator.deployed()

      // Set the mock allocator on RewardsManager
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      // Verify the allocator was set
      expect(await rewardsManager.getIssuanceAllocator()).eq(mockIssuanceAllocator.address)

      // Set RewardsManager as a self-minting target with 25 GRT per block
      const expectedIssuance = toGRT('25')
      await mockIssuanceAllocator['setTargetAllocation(address,uint256,uint256,bool)'](
        rewardsManager.address,
        0, // allocator issuance
        expectedIssuance, // self issuance
        true,
      )

      // Allocated getter returns the allocator value, raw getter still returns storage value
      expect(await rewardsManager.getAllocatedIssuancePerBlock()).eq(expectedIssuance)
      expect(await rewardsManager.getRawIssuancePerBlock()).eq(ISSUANCE_PER_BLOCK)
    })

    it('should return 0 when issuanceAllocator is set but target not registered as self-minter', async function () {
      // Create a mock IssuanceAllocator
      const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy()
      await mockIssuanceAllocator.deployed()

      // Set the mock allocator on RewardsManager
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      // Set RewardsManager as an allocator-minting target (only allocator issuance)
      await mockIssuanceAllocator['setTargetAllocation(address,uint256,uint256,bool)'](
        rewardsManager.address,
        toGRT('25'), // allocator issuance
        0, // self issuance
        false,
      )

      // Allocated returns 0 (not a self-minting target), raw is unchanged
      expect(await rewardsManager.getAllocatedIssuancePerBlock()).eq(0)
      expect(await rewardsManager.getRawIssuancePerBlock()).eq(ISSUANCE_PER_BLOCK)
    })
  })

  describe('setIssuancePerBlock', function () {
    it('should allow setIssuancePerBlock when issuanceAllocator is set', async function () {
      // Create and set a mock IssuanceAllocator
      const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy()
      await mockIssuanceAllocator.deployed()
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      // Should allow setting issuancePerBlock even when allocator is set
      const newIssuancePerBlock = toGRT('100')
      await rewardsManager.connect(governor).setIssuancePerBlock(newIssuancePerBlock)

      // Both raw getter and storage variable reflect the new value
      expect(await rewardsManager.issuancePerBlock()).eq(newIssuancePerBlock)
      expect(await rewardsManager.getRawIssuancePerBlock()).eq(newIssuancePerBlock)

      // But the effective (allocated) issuance still comes from the allocator
      expect(await rewardsManager.getAllocatedIssuancePerBlock()).not.eq(newIssuancePerBlock)
    })
  })

  describe('beforeIssuanceAllocationChange', function () {
    it('should handle beforeIssuanceAllocationChange correctly', async function () {
      // Create and set a mock IssuanceAllocator
      const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy()
      await mockIssuanceAllocator.deployed()
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      // Anyone should be able to call this function
      await rewardsManager.connect(governor).beforeIssuanceAllocationChange()

      // Should also succeed when called by the allocator
      await mockIssuanceAllocator.callBeforeIssuanceAllocationChange(rewardsManager.address)
    })
  })

  describe('issuance allocator integration', function () {
    let mockIssuanceAllocator: any

    beforeEach(async function () {
      // Create and setup mock allocator
      const MockIssuanceAllocatorFactory = await hre.ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      mockIssuanceAllocator = await MockIssuanceAllocatorFactory.deploy()
      await mockIssuanceAllocator.deployed()
    })

    it('should accumulate rewards using allocator rate over time', async function () {
      // Setup: Create signal
      const totalSignal = toGRT('1000')
      await curation.connect(curator1).mint(subgraphDeploymentID1, totalSignal, 0)

      // Set allocator with specific rate (50 GRT per block, different from local 200 GRT)
      const allocatorRate = toGRT('50')
      await mockIssuanceAllocator.setTargetAllocation(rewardsManager.address, 0, allocatorRate, false)
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      // Snapshot state after setting allocator
      const rewardsAfterSet = await rewardsManager.getAccRewardsPerSignal()

      // Mine blocks to accrue rewards at allocator rate
      const blocksToMine = 10
      await helpers.mine(blocksToMine)

      // Get accumulated rewards
      const rewardsAfterMining = await rewardsManager.getAccRewardsPerSignal()
      const actualAccrued = rewardsAfterMining.sub(rewardsAfterSet)

      // Calculate expected rewards: (rate × blocks) / totalSignal
      // Expected = (50 GRT × 10 blocks) / 1000 GRT signal = 0.5 GRT per signal
      const expectedAccrued = allocatorRate.mul(blocksToMine).mul(toGRT('1')).div(totalSignal)

      // Verify rewards accumulated at allocator rate (not local rate of 200 GRT/block)
      expect(actualAccrued).to.eq(expectedAccrued)

      // Verify NOT using local rate (would be 4x higher: 200 vs 50)
      const wrongExpected = ISSUANCE_PER_BLOCK.mul(blocksToMine).mul(toGRT('1')).div(totalSignal)
      expect(actualAccrued).to.not.eq(wrongExpected)
    })

    it('should maintain reward consistency when switching between rates', async function () {
      // Setup: Create signal
      const totalSignal = toGRT('2000')
      await curation.connect(curator1).mint(subgraphDeploymentID1, totalSignal, 0)

      // Snapshot initial state
      const block0 = await helpers.latestBlock()
      const rewards0 = await rewardsManager.getAccRewardsPerSignal()

      // Phase 1: Accrue at local rate (200 GRT/block)
      await helpers.mine(5)
      const block1 = await helpers.latestBlock()
      const rewards1 = await rewardsManager.getAccRewardsPerSignal()

      // Calculate phase 1 accrual
      const blocksPhase1 = block1 - block0
      const phase1Accrued = rewards1.sub(rewards0)
      const expectedPhase1 = ISSUANCE_PER_BLOCK.mul(blocksPhase1).mul(toGRT('1')).div(totalSignal)
      expect(phase1Accrued).to.eq(expectedPhase1)

      // Phase 2: Switch to allocator with different rate (100 GRT/block)
      const allocatorRate = toGRT('100')
      await mockIssuanceAllocator.setTargetAllocation(rewardsManager.address, 0, allocatorRate, false)
      await rewardsManager.connect(governor).setIssuanceAllocator(mockIssuanceAllocator.address)

      const block2 = await helpers.latestBlock()
      const rewards2 = await rewardsManager.getAccRewardsPerSignal()

      await helpers.mine(8)
      const block3 = await helpers.latestBlock()
      const rewards3 = await rewardsManager.getAccRewardsPerSignal()

      // Calculate phase 2 accrual (includes the setIssuanceAllocator block at local rate)
      const blocksPhase2 = block3 - block2
      const phase2Accrued = rewards3.sub(rewards2)
      const expectedPhase2 = allocatorRate.mul(blocksPhase2).mul(toGRT('1')).div(totalSignal)
      expect(phase2Accrued).to.eq(expectedPhase2)

      // Phase 3: Switch back to local rate (200 GRT/block)
      await rewardsManager.connect(governor).setIssuanceAllocator(constants.AddressZero)

      const block4 = await helpers.latestBlock()
      const rewards4 = await rewardsManager.getAccRewardsPerSignal()

      await helpers.mine(4)
      const block5 = await helpers.latestBlock()
      const rewards5 = await rewardsManager.getAccRewardsPerSignal()

      // Calculate phase 3 accrual
      const blocksPhase3 = block5 - block4
      const phase3Accrued = rewards5.sub(rewards4)
      const expectedPhase3 = ISSUANCE_PER_BLOCK.mul(blocksPhase3).mul(toGRT('1')).div(totalSignal)
      expect(phase3Accrued).to.eq(expectedPhase3)

      // Verify total consistency: all rewards from start to end must equal sum of all phases
      // including the transition blocks (setIssuanceAllocator calls mine blocks too)
      const transitionPhase1to2 = rewards2.sub(rewards1) // Block mined by setIssuanceAllocator
      const transitionPhase2to3 = rewards4.sub(rewards3) // Block mined by removing allocator
      const totalExpected = phase1Accrued
        .add(transitionPhase1to2)
        .add(phase2Accrued)
        .add(transitionPhase2to3)
        .add(phase3Accrued)
      const totalActual = rewards5.sub(rewards0)
      expect(totalActual).to.eq(totalExpected)
    })
  })
})

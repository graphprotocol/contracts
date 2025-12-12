import { expect } from 'chai'
import hre from 'hardhat'
const { ethers } = hre

import { deployTestGraphToken, getTestAccounts } from '../common/fixtures'
import { deployDirectAllocation, deployIssuanceAllocator } from './fixtures'
import { expectCustomError } from './optimizationHelpers'

describe('IssuanceAllocator - Default Allocation', () => {
  let accounts
  let graphToken
  let issuanceAllocator
  let target1
  let target2
  let target3
  let addresses

  const MILLION = 1_000_000n
  const issuancePerBlock = ethers.parseEther('100')

  beforeEach(async () => {
    accounts = await getTestAccounts()

    // Deploy fresh contracts for each test
    graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, accounts.governor, issuancePerBlock)

    target1 = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    target2 = await deployDirectAllocation(graphTokenAddress, accounts.governor)
    target3 = await deployDirectAllocation(graphTokenAddress, accounts.governor)

    addresses = {
      issuanceAllocator: await issuanceAllocator.getAddress(),
      target1: await target1.getAddress(),
      target2: await target2.getAddress(),
      target3: await target3.getAddress(),
      graphToken: graphTokenAddress,
    }

    // Grant minter role to issuanceAllocator
    await (graphToken as any).addMinter(addresses.issuanceAllocator)
  })

  describe('Initialization', () => {
    it('should initialize with default allocation at index 0', async () => {
      const targetCount = await issuanceAllocator.getTargetCount()
      expect(targetCount).to.equal(1n)

      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(ethers.ZeroAddress)
    })

    it('should initialize with 100% allocation to default target', async () => {
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const allocation = await issuanceAllocator.getTargetAllocation(defaultAddress)

      expect(allocation.totalAllocationPPM).to.equal(MILLION)
      expect(allocation.allocatorMintingPPM).to.equal(MILLION)
      expect(allocation.selfMintingPPM).to.equal(0n)
    })

    it('should report total allocation as 0% when default is address(0)', async () => {
      const totalAllocation = await issuanceAllocator.getTotalAllocation()

      // When default is address(0), it is treated as unallocated for reporting purposes
      expect(totalAllocation.totalAllocationPPM).to.equal(0n)
      expect(totalAllocation.allocatorMintingPPM).to.equal(0n)
      expect(totalAllocation.selfMintingPPM).to.equal(0n)
    })
  })

  describe('100% Allocation Invariant', () => {
    it('should auto-adjust default allocation when setting normal target allocation', async () => {
      const allocation1PPM = 300_000n // 30%

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, allocation1PPM)

      // Check target1 has correct allocation
      const target1Allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(target1Allocation.totalAllocationPPM).to.equal(allocation1PPM)

      // Check default allocation was auto-adjusted
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationPPM).to.equal(MILLION - allocation1PPM)

      // Check reported total (excludes default since it's address(0))
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationPPM).to.equal(allocation1PPM)
    })

    it('should maintain 100% invariant with multiple targets', async () => {
      const allocation1PPM = 200_000n // 20%
      const allocation2PPM = 350_000n // 35%
      const allocation3PPM = 150_000n // 15%

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, allocation1PPM)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, allocation2PPM)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target3, allocation3PPM)

      // Check default allocation is 30% (100% - 20% - 35% - 15%)
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      const expectedDefault = MILLION - allocation1PPM - allocation2PPM - allocation3PPM
      expect(defaultAllocation.totalAllocationPPM).to.equal(expectedDefault)

      // Check reported total (excludes default since it's address(0))
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationPPM).to.equal(allocation1PPM + allocation2PPM + allocation3PPM)
    })

    it('should allow 0% default allocation when all allocation is assigned', async () => {
      const allocation1PPM = 600_000n // 60%
      const allocation2PPM = 400_000n // 40%

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, allocation1PPM)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, allocation2PPM)

      // Check default allocation is 0%
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationPPM).to.equal(0n)

      // Check reported total is 100% (default has 0%, so exclusion doesn't matter)
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationPPM).to.equal(MILLION)
    })

    it('should revert if non-default allocations exceed 100%', async () => {
      const allocation1PPM = 600_000n // 60%
      const allocation2PPM = 500_000n // 50% (total would be 110%)

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, allocation1PPM)

      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](addresses.target2, allocation2PPM),
        issuanceAllocator,
        'InsufficientAllocationAvailable',
      )
    })

    it('should adjust default when removing a target allocation', async () => {
      // Set up initial allocations
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 300_000n)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, 200_000n)

      // Default should be 50%
      let defaultAddress = await issuanceAllocator.getTargetAt(0)
      let defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationPPM).to.equal(500_000n)

      // Remove target1 allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 0, 0, false)

      // Default should now be 80%
      defaultAddress = await issuanceAllocator.getTargetAt(0)
      defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationPPM).to.equal(800_000n)

      // Reported total excludes default (only target2's 20% is reported)
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationPPM).to.equal(200_000n)
    })

    it('should handle self-minting allocations correctly in 100% invariant', async () => {
      const allocator1 = 200_000n
      const self1 = 100_000n
      const allocator2 = 300_000n
      const self2 = 50_000n

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, allocator1, self1)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target2, allocator2, self2)

      // Total non-default: 20% + 10% + 30% + 5% = 65%
      // Default should be: 35%
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationPPM).to.equal(350_000n)

      // Reported total excludes default (only target1+target2's 65% is reported)
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationPPM).to.equal(allocator1 + self1 + allocator2 + self2)
      expect(totalAllocation.selfMintingPPM).to.equal(self1 + self2)
    })
  })

  describe('setDefaultAllocationAddress', () => {
    it('should allow governor to change default allocation address', async () => {
      const newDefaultAddress = addresses.target1

      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(newDefaultAddress)

      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(newDefaultAddress)
    })

    it('should maintain allocation when changing default address', async () => {
      // Set a target allocation first
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, 400_000n)

      // Default should be 60%
      let defaultAddress = await issuanceAllocator.getTargetAt(0)
      let defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationPPM).to.equal(600_000n)

      // Change default address
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target1)

      // Check new address has the same allocation
      defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(addresses.target1)
      defaultAllocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(defaultAllocation.totalAllocationPPM).to.equal(600_000n)

      // Old address should have zero allocation
      const oldAllocation = await issuanceAllocator.getTargetAllocation(ethers.ZeroAddress)
      expect(oldAllocation.totalAllocationPPM).to.equal(0n)
    })

    it('should emit DefaultAllocationAddressUpdated event', async () => {
      const newDefaultAddress = addresses.target1

      await expect(issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(newDefaultAddress))
        .to.emit(issuanceAllocator, 'DefaultAllocationAddressUpdated')
        .withArgs(ethers.ZeroAddress, newDefaultAddress)
    })

    it('should be no-op when setting to same address', async () => {
      const currentAddress = await issuanceAllocator.getTargetAt(0)

      const tx = await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(currentAddress)
      const receipt = await tx.wait()

      // Should not emit event when no-op
      const events = receipt!.logs.filter((log: any) => {
        try {
          return issuanceAllocator.interface.parseLog(log)?.name === 'DefaultAllocationAddressUpdated'
        } catch {
          return false
        }
      })
      expect(events.length).to.equal(0)
    })

    it('should revert when non-governor tries to change default address', async () => {
      await expect(
        issuanceAllocator.connect(accounts.user).setDefaultAllocationAddress(addresses.target1),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when trying to set default to a normally allocated target', async () => {
      // Set target1 as a normal allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 300_000n)

      // Try to set target1 as default should fail
      await expectCustomError(
        issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target1),
        issuanceAllocator,
        'CannotSetDefaultToAllocatedTarget',
      )
    })

    it('should allow changing back to zero address', async () => {
      // Change to target1
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target1)

      // Change back to zero address
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(ethers.ZeroAddress)

      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(ethers.ZeroAddress)
    })
  })

  describe('setTargetAllocation restrictions', () => {
    it('should revert with zero address error when default target is address(0)', async () => {
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(ethers.ZeroAddress)

      // When default is address(0), the zero address check happens first
      await expectCustomError(
        issuanceAllocator.connect(accounts.governor)['setTargetAllocation(address,uint256)'](defaultAddress, 500_000n),
        issuanceAllocator,
        'TargetAddressCannotBeZero',
      )
    })

    it('should revert when trying to set allocation for changed default target', async () => {
      // Change default to target1
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target1)

      // Should not be able to set allocation for target1 now
      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](addresses.target1, 500_000n),
        issuanceAllocator,
        'CannotSetAllocationForDefaultTarget',
      )
    })

    it('should allow setting allocation for previous default address after it changes', async () => {
      // Change default to target1
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target1)

      // Should now be able to set allocation for old default (zero address would fail for other reasons, use target2)
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target2)

      // Now target1 is no longer default, should be able to allocate to it
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 300_000n)

      const allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(allocation.totalAllocationPPM).to.equal(300_000n)
    })

    it('should revert when trying to set allocation for address(0) when default is not address(0)', async () => {
      // Change default to target1
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target1)

      // Try to set allocation for address(0) directly should fail
      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](ethers.ZeroAddress, 300_000n),
        issuanceAllocator,
        'TargetAddressCannotBeZero',
      )
    })
  })

  describe('Distribution with default allocation', () => {
    it('should not mint to zero address when default is unset', async () => {
      // Set a normal target allocation (this is block 1)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 400_000n)

      // Distribute (this is block 2, so we distribute for block 1->2 = 1 block since last distribution)
      await issuanceAllocator.distributeIssuance()

      // Target1 should receive 40% of issuance for the block between setTargetAllocation and distributeIssuance
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      const expectedTarget1 = (issuancePerBlock * 400_000n) / MILLION
      expect(target1Balance).to.equal(expectedTarget1)

      // Zero address should have nothing (cannot be minted to)
      const zeroBalance = await graphToken.balanceOf(ethers.ZeroAddress)
      expect(zeroBalance).to.equal(0n)

      // The 60% for default (zero address) is effectively burned/not minted
    })

    it('should mint to default address when it is set', async () => {
      // Distribute any pending issuance first to start fresh
      await issuanceAllocator.distributeIssuance()

      // Change default to target3
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target3)

      // Set target1 allocation using evenIfDistributionPending to avoid premature distribution
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 300_000n, 0n, true)

      // Distribute once (exactly 1 block with the new allocations)
      await issuanceAllocator.distributeIssuance()

      // Target1 should receive 30% for 1 block (from last distributeIssuance call)
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      const expectedTarget1 = (issuancePerBlock * 300_000n) / MILLION
      expect(target1Balance).to.equal(expectedTarget1)

      // Target3 (default) should receive:
      // - 100% for 2 blocks (from initial distributeIssuance to setTargetAllocation)
      // - 70% for 1 block (from setTargetAllocation to final distributeIssuance)
      const target3Balance = await graphToken.balanceOf(addresses.target3)
      const expectedTarget3 = issuancePerBlock * 2n + (issuancePerBlock * 700_000n) / MILLION
      expect(target3Balance).to.equal(expectedTarget3)
    })

    it('should distribute correctly with multiple targets and default', async () => {
      // Distribute any pending issuance first to start fresh
      await issuanceAllocator.distributeIssuance()

      // Set default to target3
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target3)

      // Set allocations using evenIfDistributionPending to avoid premature distributions
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target1, 200_000n, 0n, true) // 20%

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,bool)'](addresses.target2, 300_000n, 0n, true) // 30%
      // Default (target3) gets 50%

      // Distribute once (exactly 1 block with the final allocations)
      await issuanceAllocator.distributeIssuance()

      // Check all balances accounting for block accumulation:
      // - target1 gets 20% for 2 blocks (from first setTargetAllocation onwards)
      // - target2 gets 30% for 1 block (from second setTargetAllocation onwards)
      // - target3 (default) gets 100% for 2 blocks + 80% for 1 block + 50% for 1 block
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      const target2Balance = await graphToken.balanceOf(addresses.target2)
      const target3Balance = await graphToken.balanceOf(addresses.target3)

      const expectedTarget1 = (issuancePerBlock * 200_000n * 2n) / MILLION
      const expectedTarget2 = (issuancePerBlock * 300_000n) / MILLION
      const expectedTarget3 =
        issuancePerBlock * 2n + (issuancePerBlock * 800_000n) / MILLION + (issuancePerBlock * 500_000n) / MILLION

      expect(target1Balance).to.equal(expectedTarget1)
      expect(target2Balance).to.equal(expectedTarget2)
      expect(target3Balance).to.equal(expectedTarget3)

      // Total minted should equal 4 blocks of issuance
      const totalMinted = target1Balance + target2Balance + target3Balance
      expect(totalMinted).to.equal(issuancePerBlock * 4n)
    })

    it('should handle distribution when default allocation is 0%', async () => {
      // Distribute any pending issuance first to start fresh
      await issuanceAllocator.distributeIssuance()

      // Default is address(0), which doesn't receive minting
      // Allocate 100% to explicit targets
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 600_000n)
      // At this point target1 has 60%, default has 40%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, 400_000n)
      // Now target1 has 60%, target2 has 40%, default has 0%

      // Distribute (1 block since last setTargetAllocation)
      await issuanceAllocator.distributeIssuance()

      // Zero address (default) should receive nothing
      const zeroBalance = await graphToken.balanceOf(ethers.ZeroAddress)
      expect(zeroBalance).to.equal(0n)

      // Target1 receives: 0% (from first distributeIssuance to first setTargetAllocation)
      //                 + 60% (from first setTargetAllocation to second setTargetAllocation)
      //                 + 60% (from second setTargetAllocation to final distributeIssuance)
      // = 120% of one block = 60% * 2 blocks
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      expect(target1Balance).to.equal((issuancePerBlock * 600_000n * 2n) / MILLION)

      // Target2 receives: 40% (from second setTargetAllocation to final distributeIssuance)
      const target2Balance = await graphToken.balanceOf(addresses.target2)
      expect(target2Balance).to.equal((issuancePerBlock * 400_000n) / MILLION)

      // Default allocation is now 0%
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationPPM).to.equal(0n)
    })
  })

  describe('View functions', () => {
    it('should return correct target count including default', async () => {
      let count = await issuanceAllocator.getTargetCount()
      expect(count).to.equal(1n) // Just default

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 300_000n)

      count = await issuanceAllocator.getTargetCount()
      expect(count).to.equal(2n) // Default + target1

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, 200_000n)

      count = await issuanceAllocator.getTargetCount()
      expect(count).to.equal(3n) // Default + target1 + target2
    })

    it('should include default in getTargets array', async () => {
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 300_000n)

      const targets = await issuanceAllocator.getTargets()
      expect(targets.length).to.equal(2)
      expect(targets[0]).to.equal(ethers.ZeroAddress) // Default at index 0
      expect(targets[1]).to.equal(addresses.target1)
    })

    it('should return correct data for default target', async () => {
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 400_000n)

      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const data = await issuanceAllocator.getTargetData(defaultAddress)

      expect(data.allocatorMintingPPM).to.equal(600_000n)
      expect(data.selfMintingPPM).to.equal(0n)
    })

    it('should report 100% total allocation when default is a real address', async () => {
      // Set target1 allocation first
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, 300_000n)

      // Change default to target2 (a real address, not address(0))
      await issuanceAllocator.connect(accounts.governor).setDefaultAllocationAddress(addresses.target2)

      // When default is a real address, it should report 100% total allocation
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationPPM).to.equal(MILLION)
      expect(totalAllocation.allocatorMintingPPM).to.equal(MILLION) // target1=30% + target2=70% = 100%
      expect(totalAllocation.selfMintingPPM).to.equal(0n)
    })
  })
})

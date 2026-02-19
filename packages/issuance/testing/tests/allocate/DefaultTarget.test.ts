import { expect } from 'chai'
import { ethers as ethersLib } from 'ethers'

import { getEthers } from '../common/ethersHelper'
import { deployTestGraphToken, getTestAccounts } from '../common/fixtures'
import { deployDirectAllocation, deployIssuanceAllocator } from './fixtures'
import { expectCustomError } from './optimizationHelpers'

describe('IssuanceAllocator - Default Allocation', () => {
  let accounts: any
  let graphToken: any
  let issuanceAllocator: any
  let target1: any
  let target2: any
  let target3: any
  let addresses: any
  let ethers: any // HH v3 ethers instance

  const issuancePerBlock = ethersLib.parseEther('100')

  beforeEach(async () => {
    ethers = await getEthers()
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
    it('should initialize with default target at index 0', async () => {
      const targetCount = await issuanceAllocator.getTargetCount()
      expect(targetCount).to.equal(1n)

      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(ethersLib.ZeroAddress)
    })

    it('should initialize with 100% allocation to default target', async () => {
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const allocation = await issuanceAllocator.getTargetAllocation(defaultAddress)

      expect(allocation.totalAllocationRate).to.equal(issuancePerBlock)
      expect(allocation.allocatorMintingRate).to.equal(issuancePerBlock)
      expect(allocation.selfMintingRate).to.equal(0n)
    })

    it('should report total allocation as 0% when default is address(0)', async () => {
      const totalAllocation = await issuanceAllocator.getTotalAllocation()

      // When default is address(0), it is treated as unallocated for reporting purposes
      expect(totalAllocation.totalAllocationRate).to.equal(0n)
      expect(totalAllocation.allocatorMintingRate).to.equal(0n)
      expect(totalAllocation.selfMintingRate).to.equal(0n)
    })
  })

  describe('100% Allocation Invariant', () => {
    it('should auto-adjust default target when setting normal target allocation', async () => {
      const allocation1Rate = ethersLib.parseEther('30') // 30%

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, allocation1Rate)

      // Check target1 has correct allocation
      const target1Allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(target1Allocation.totalAllocationRate).to.equal(allocation1Rate)

      // Check default target was auto-adjusted
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationRate).to.equal(issuancePerBlock - allocation1Rate)

      // Check reported total (excludes default since it's address(0))
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationRate).to.equal(allocation1Rate)
    })

    it('should maintain 100% invariant with multiple targets', async () => {
      const allocation1Rate = ethersLib.parseEther('20') // 20%
      const allocation2Rate = ethersLib.parseEther('35') // 35%
      const allocation3Rate = ethersLib.parseEther('15') // 15%

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, allocation1Rate)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, allocation2Rate)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target3, allocation3Rate)

      // Check default target is 30% (100% - 20% - 35% - 15%)
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      const expectedDefault = issuancePerBlock - allocation1Rate - allocation2Rate - allocation3Rate
      expect(defaultAllocation.totalAllocationRate).to.equal(expectedDefault)

      // Check reported total (excludes default since it's address(0))
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationRate).to.equal(allocation1Rate + allocation2Rate + allocation3Rate)
    })

    it('should allow 0% default target when all allocation is assigned', async () => {
      const allocation1Rate = ethersLib.parseEther('60') // 60%
      const allocation2Rate = ethersLib.parseEther('40') // 40%

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, allocation1Rate)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, allocation2Rate)

      // Check default target is 0%
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationRate).to.equal(0n)

      // Check reported total is 100% (default has 0%, so exclusion doesn't matter)
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationRate).to.equal(issuancePerBlock)
    })

    it('should revert if non-default targets exceed 100%', async () => {
      const allocation1Rate = ethersLib.parseEther('60') // 60%
      const allocation2Rate = ethersLib.parseEther('50') // 50% (total would be 110%)

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, allocation1Rate)

      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](addresses.target2, allocation2Rate),
        issuanceAllocator,
        'InsufficientAllocationAvailable',
      )
    })

    it('should adjust default when removing a target allocation', async () => {
      // Set up initial allocations
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('30'))
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, ethersLib.parseEther('20'))

      // Default should be 50%
      let defaultAddress = await issuanceAllocator.getTargetAt(0)
      let defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationRate).to.equal(ethersLib.parseEther('50'))

      // Remove target1 allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.target1, 0, 0)

      // Default should now be 80%
      defaultAddress = await issuanceAllocator.getTargetAt(0)
      defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationRate).to.equal(ethersLib.parseEther('80'))

      // Reported total excludes default (only target2's 20% is reported)
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationRate).to.equal(ethersLib.parseEther('20'))
    })

    it('should handle self-minting allocations correctly in 100% invariant', async () => {
      const allocator1 = ethersLib.parseEther('20')
      const self1 = ethersLib.parseEther('10')
      const allocator2 = ethersLib.parseEther('30')
      const self2 = ethersLib.parseEther('5')

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
      expect(defaultAllocation.totalAllocationRate).to.equal(ethersLib.parseEther('35'))

      // Reported total excludes default (only target1+target2's 65% is reported)
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationRate).to.equal(allocator1 + self1 + allocator2 + self2)
      expect(totalAllocation.selfMintingRate).to.equal(self1 + self2)
    })
  })

  describe('setDefaultTarget', () => {
    it('should allow governor to change default target address', async () => {
      const newDefaultAddress = addresses.target1

      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(newDefaultAddress)

      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(newDefaultAddress)
    })

    it('should maintain allocation when changing default address', async () => {
      // Set a target allocation first
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, ethersLib.parseEther('40'))

      // Default should be 60%
      let defaultAddress = await issuanceAllocator.getTargetAt(0)
      let defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationRate).to.equal(ethersLib.parseEther('60'))

      // Change default address
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target1)

      // Check new address has the same allocation
      defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(addresses.target1)
      defaultAllocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(defaultAllocation.totalAllocationRate).to.equal(ethersLib.parseEther('60'))

      // Old address should have zero allocation
      const oldAllocation = await issuanceAllocator.getTargetAllocation(ethersLib.ZeroAddress)
      expect(oldAllocation.totalAllocationRate).to.equal(0n)
    })

    it('should emit DefaultTargetUpdated event', async () => {
      const newDefaultAddress = addresses.target1

      await expect(issuanceAllocator.connect(accounts.governor).setDefaultTarget(newDefaultAddress))
        .to.emit(issuanceAllocator, 'DefaultTargetUpdated')
        .withArgs(ethersLib.ZeroAddress, newDefaultAddress)
    })

    it('should be no-op when setting to same address', async () => {
      const currentAddress = await issuanceAllocator.getTargetAt(0)

      const tx = await issuanceAllocator.connect(accounts.governor).setDefaultTarget(currentAddress)
      const receipt = await tx.wait()

      // Should not emit event when no-op
      const events = receipt!.logs.filter((log: any) => {
        try {
          return issuanceAllocator.interface.parseLog(log)?.name === 'DefaultTargetUpdated'
        } catch {
          return false
        }
      })
      expect(events.length).to.equal(0)
    })

    it('should revert when non-governor tries to change default address', async () => {
      await expect(
        issuanceAllocator.connect(accounts.user).setDefaultTarget(addresses.target1),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when non-governor tries to change default address with explicit fromBlockNumber', async () => {
      const currentBlock = await ethers.provider.getBlockNumber()
      await expect(
        issuanceAllocator.connect(accounts.user)['setDefaultTarget(address,uint256)'](addresses.target1, currentBlock),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')
    })

    it('should return false when trying to change default address while paused without explicit fromBlockNumber', async () => {
      // Grant pause role and pause
      const PAUSE_ROLE = ethersLib.keccak256(ethersLib.toUtf8Bytes('PAUSE_ROLE'))
      await issuanceAllocator.connect(accounts.governor).grantRole(PAUSE_ROLE, accounts.governor.address)
      await issuanceAllocator.connect(accounts.governor).pause()

      // Try to change default without explicit fromBlockNumber - should return false (checked via staticCall)
      const result = await issuanceAllocator.connect(accounts.governor).setDefaultTarget.staticCall(addresses.target3)
      expect(result).to.equal(false)

      // Verify allocation didn't change
      const currentDefault = await issuanceAllocator.getTargetAt(0)
      expect(currentDefault).to.equal(ethersLib.ZeroAddress)

      // Should succeed with explicit minDistributedBlock that has been reached
      const lastDistributionBlock = (await issuanceAllocator.getDistributionState()).lastDistributionBlock
      await issuanceAllocator
        .connect(accounts.governor)
        ['setDefaultTarget(address,uint256)'](addresses.target3, lastDistributionBlock)

      const newDefault = await issuanceAllocator.getTargetAt(0)
      expect(newDefault).to.equal(addresses.target3)
    })

    it('should revert when trying to set default to a normally allocated target', async () => {
      // Set target1 as a normal allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('30'))

      // Try to set target1 as default should fail
      await expectCustomError(
        issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target1),
        issuanceAllocator,
        'CannotSetDefaultToAllocatedTarget',
      )
    })

    it('should allow changing back to zero address', async () => {
      // Change to target1
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target1)

      // Change back to zero address
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(ethersLib.ZeroAddress)

      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(ethersLib.ZeroAddress)
    })
  })

  describe('setTargetAllocation restrictions', () => {
    it('should revert with zero address error when default target is address(0)', async () => {
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(ethersLib.ZeroAddress)

      // When default is address(0), the zero address check happens first
      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](defaultAddress, ethersLib.parseEther('50')),
        issuanceAllocator,
        'TargetAddressCannotBeZero',
      )
    })

    it('should revert when trying to set allocation for changed default target', async () => {
      // Change default to target1
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target1)

      // Should not be able to set allocation for target1 now
      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('50')),
        issuanceAllocator,
        'CannotSetAllocationForDefaultTarget',
      )
    })

    it('should allow setting allocation for previous default address after it changes', async () => {
      // Change default to target1
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target1)

      // Change default to target2 (target1 is no longer the default)
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target2)

      // Now target1 can receive a normal allocation since it's no longer the default
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('30'))

      const allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(allocation.totalAllocationRate).to.equal(ethersLib.parseEther('30'))
    })

    it('should revert when trying to set allocation for address(0) when default is not address(0)', async () => {
      // Change default to target1
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target1)

      // Try to set allocation for address(0) directly should fail
      await expectCustomError(
        issuanceAllocator
          .connect(accounts.governor)
          ['setTargetAllocation(address,uint256)'](ethersLib.ZeroAddress, ethersLib.parseEther('30')),
        issuanceAllocator,
        'TargetAddressCannotBeZero',
      )
    })
  })

  describe('Distribution with default target', () => {
    it('should not mint to zero address when default is unset', async () => {
      // Set a normal target allocation (this is block 1)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('40'))

      // Distribute (this is block 2, so we distribute for block 1->2 = 1 block since last distribution)
      await issuanceAllocator.distributeIssuance()

      // Target1 should receive 40% of issuance for the block between setTargetAllocation and distributeIssuance
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      const expectedTarget1 = (issuancePerBlock * ethersLib.parseEther('40')) / issuancePerBlock
      expect(target1Balance).to.equal(expectedTarget1)

      // Zero address should have nothing (cannot be minted to)
      const zeroBalance = await graphToken.balanceOf(ethersLib.ZeroAddress)
      expect(zeroBalance).to.equal(0n)

      // The 60% for default (zero address) is effectively burned/not minted
    })

    it('should mint to default address when it is set', async () => {
      // Change default to target3
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target3)

      // Set target1 allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('30'))

      // Distribute to settle issuance
      await issuanceAllocator.distributeIssuance()

      // Target1 should receive 30% for 1 block
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      const expectedTarget1 = (issuancePerBlock * ethersLib.parseEther('30')) / issuancePerBlock
      expect(target1Balance).to.equal(expectedTarget1)

      // Target3 (default) should receive:
      // - 100% for 1 block (from setDefaultTarget to setTargetAllocation)
      // - 70% for 1 block (from setTargetAllocation to distributeIssuance)
      const target3Balance = await graphToken.balanceOf(addresses.target3)
      const expectedTarget3 = issuancePerBlock + ethersLib.parseEther('70')
      expect(target3Balance).to.equal(expectedTarget3)
    })

    it('should distribute correctly with multiple targets and default', async () => {
      // Set default to target3
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target3)

      // Set allocations (target3 gets remaining 50% as default)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('20')) // 20%

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, ethersLib.parseEther('30')) // 30%

      // Distribute to settle issuance
      await issuanceAllocator.distributeIssuance()

      // Check balances:
      // - target1 gets 20% for 2 blocks (from first setTargetAllocation onwards)
      // - target2 gets 30% for 1 block (from second setTargetAllocation onwards)
      // - target3 (default) gets 100% for 1 block + 80% for 1 block + 50% for 1 block
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      const target2Balance = await graphToken.balanceOf(addresses.target2)
      const target3Balance = await graphToken.balanceOf(addresses.target3)

      const expectedTarget1 = (issuancePerBlock * ethersLib.parseEther('20') * 2n) / issuancePerBlock
      const expectedTarget2 = (issuancePerBlock * ethersLib.parseEther('30')) / issuancePerBlock
      const expectedTarget3 = issuancePerBlock + ethersLib.parseEther('80') + ethersLib.parseEther('50')

      expect(target1Balance).to.equal(expectedTarget1)
      expect(target2Balance).to.equal(expectedTarget2)
      expect(target3Balance).to.equal(expectedTarget3)

      // Total minted should equal 3 blocks of issuance
      const totalMinted = target1Balance + target2Balance + target3Balance
      expect(totalMinted).to.equal(issuancePerBlock * 3n)
    })

    it('should handle distribution when default target is 0%', async () => {
      // Allocate 100% to explicit targets (default gets 0%)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('60'))
      // At this point target1 has 60%, default has 40%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, ethersLib.parseEther('40'))
      // Now target1 has 60%, target2 has 40%, default has 0%

      // Distribute (1 block since last setTargetAllocation)
      await issuanceAllocator.distributeIssuance()

      // Zero address (default) should receive nothing
      const zeroBalance = await graphToken.balanceOf(ethersLib.ZeroAddress)
      expect(zeroBalance).to.equal(0n)

      // Target1 receives: 0% (from first distributeIssuance to first setTargetAllocation)
      //                 + 60% (from first setTargetAllocation to second setTargetAllocation)
      //                 + 60% (from second setTargetAllocation to final distributeIssuance)
      // = 120% of one block = 60% * 2 blocks
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      expect(target1Balance).to.equal((issuancePerBlock * ethersLib.parseEther('60') * 2n) / issuancePerBlock)

      // Target2 receives: 40% (from second setTargetAllocation to final distributeIssuance)
      const target2Balance = await graphToken.balanceOf(addresses.target2)
      expect(target2Balance).to.equal((issuancePerBlock * ethersLib.parseEther('40')) / issuancePerBlock)

      // Default allocation is now 0%
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationRate).to.equal(0n)
    })

    it('should distribute during setDefaultTarget when using default behavior', async () => {
      // Change default to target3 using the simple variant (no explicit fromBlockNumber)
      // This should distribute issuance up to current block before changing the default
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target3)

      // Set target1 allocation
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256,uint256)'](addresses.target1, ethersLib.parseEther('30'), 0n, 0)

      // Distribute once more
      await issuanceAllocator.distributeIssuance()

      // Target3 (default) should receive:
      // - 0% for 1 block (setDefaultTarget distributes to old default (zero address) before changing)
      // - 100% for 1 block (from setDefaultTarget to setTargetAllocation)
      // - 70% for 1 block (from setTargetAllocation to final distributeIssuance)
      const target3Balance = await graphToken.balanceOf(addresses.target3)
      const expectedTarget3 = issuancePerBlock + ethersLib.parseEther('70')
      expect(target3Balance).to.equal(expectedTarget3)

      // Target1 should receive 30% for 1 block
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      const expectedTarget1 = (issuancePerBlock * ethersLib.parseEther('30')) / issuancePerBlock
      expect(target1Balance).to.equal(expectedTarget1)
    })

    it('should handle changing default to address that previously had normal allocation', async () => {
      // Scenario: target1 has normal allocation → removed (0%) → set as default
      // This tests for stale data issues

      // Set target1 as normal allocation with 30%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('30'))

      let allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(allocation.totalAllocationRate).to.equal(ethersLib.parseEther('30'))

      // Remove target1's allocation (set to 0%)
      await issuanceAllocator.connect(accounts.governor)['setTargetAllocation(address,uint256)'](addresses.target1, 0n)

      // Verify target1 is no longer in targetAddresses (except if it's at index 0, which it's not)
      const targetCount = await issuanceAllocator.getTargetCount()
      const targets = []
      for (let i = 0; i < targetCount; i++) {
        targets.push(await issuanceAllocator.getTargetAt(i))
      }
      expect(targets).to.not.include(addresses.target1) // Should not be in list anymore

      // Now set target1 as default - should work and not have stale allocation data
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target1)

      // Verify target1 is now default with 100% allocation (since no other targets)
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(defaultAddress).to.equal(addresses.target1)

      allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      expect(allocation.totalAllocationRate).to.equal(issuancePerBlock) // Should have full allocation as default
    })

    it('should handle changing default when default has 0% allocation', async () => {
      // Allocate 100% to other targets so default has 0%
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('60'))

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, ethersLib.parseEther('40'))

      // Default should now have 0%
      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const defaultAllocation = await issuanceAllocator.getTargetAllocation(defaultAddress)
      expect(defaultAllocation.totalAllocationRate).to.equal(0n)

      // Change default to target3
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target3)

      // New default should have 0% (same as old default)
      const newDefaultAddress = await issuanceAllocator.getTargetAt(0)
      expect(newDefaultAddress).to.equal(addresses.target3)

      const newDefaultAllocation = await issuanceAllocator.getTargetAllocation(addresses.target3)
      expect(newDefaultAllocation.totalAllocationRate).to.equal(0n)

      // Other allocations should be maintained
      const target1Allocation = await issuanceAllocator.getTargetAllocation(addresses.target1)
      const target2Allocation = await issuanceAllocator.getTargetAllocation(addresses.target2)
      expect(target1Allocation.totalAllocationRate).to.equal(ethersLib.parseEther('60'))
      expect(target2Allocation.totalAllocationRate).to.equal(ethersLib.parseEther('40'))
    })

    it('should handle changing from initial address(0) default without errors', async () => {
      // Verify initial state: default is address(0)
      const initialDefault = await issuanceAllocator.getTargetAt(0)
      expect(initialDefault).to.equal(ethersLib.ZeroAddress)

      // Add a normal allocation so there's pending issuance to distribute
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('40'))

      // Mine a few blocks to accumulate issuance
      await ethers.provider.send('evm_mine', [])
      await ethers.provider.send('evm_mine', [])

      // Change default from address(0) to target2
      // This should:
      // 1. Call _handleDistributionBeforeAllocation(address(0), ...) - should not revert
      // 2. Call _notifyTarget(address(0)) - should return early safely
      // 3. Delete allocationTargets[address(0)] - should not cause issues
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target2)

      // Verify the change succeeded
      const newDefault = await issuanceAllocator.getTargetAt(0)
      expect(newDefault).to.equal(addresses.target2)

      // Verify address(0) received no tokens (can't mint to zero address)
      const zeroAddressBalance = await graphToken.balanceOf(ethersLib.ZeroAddress)
      expect(zeroAddressBalance).to.equal(0n)

      // Distribute and verify target2 (new default) receives correct allocation
      await issuanceAllocator.distributeIssuance()

      // Target2 should have received 60% for 1 block (from setDefaultTarget to distributeIssuance)
      const target2Balance = await graphToken.balanceOf(addresses.target2)
      const expectedTarget2 = (issuancePerBlock * ethersLib.parseEther('60')) / issuancePerBlock
      expect(target2Balance).to.equal(expectedTarget2)

      // Target1 should have accumulated tokens across multiple blocks
      const target1Balance = await graphToken.balanceOf(addresses.target1)
      expect(target1Balance).to.be.gt(0n) // Should have received something

      // Verify lastChangeNotifiedBlock was preserved for the new default (not overwritten to 0 from address(0))
      const target2Data = await issuanceAllocator.getTargetData(addresses.target2)
      const currentBlock = await ethers.provider.getBlockNumber()
      expect(target2Data.lastChangeNotifiedBlock).to.be.gt(0n)
      expect(target2Data.lastChangeNotifiedBlock).to.be.lte(currentBlock)
    })

    it('should not transfer future notification block from old default to new default', async () => {
      // Set initial default to target1
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target1)

      // Force a future notification block on target1 (the current default)
      const currentBlock = await ethers.provider.getBlockNumber()
      const futureBlock = currentBlock + 100
      await issuanceAllocator
        .connect(accounts.governor)
        .forceTargetNoChangeNotificationBlock(addresses.target1, futureBlock)

      // Verify target1 has the future block set
      const target1DataBefore = await issuanceAllocator.getTargetData(addresses.target1)
      expect(target1DataBefore.lastChangeNotifiedBlock).to.equal(futureBlock)

      // Change default from target1 to target2
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target2)

      // Verify target2 (new default) has its own notification block (current block), not the future block from target1
      const target2Data = await issuanceAllocator.getTargetData(addresses.target2)
      const blockAfterChange = await ethers.provider.getBlockNumber()

      // target2 should have been notified at the current block, not inherit the future block
      expect(target2Data.lastChangeNotifiedBlock).to.equal(blockAfterChange)
      expect(target2Data.lastChangeNotifiedBlock).to.not.equal(futureBlock)
      expect(target2Data.lastChangeNotifiedBlock).to.be.lt(futureBlock)

      // Old default (target1) should no longer have data (it was removed)
      const target1DataAfter = await issuanceAllocator.getTargetData(addresses.target1)
      expect(target1DataAfter.lastChangeNotifiedBlock).to.equal(0)
    })
  })

  describe('View functions', () => {
    it('should return correct target count including default', async () => {
      let count = await issuanceAllocator.getTargetCount()
      expect(count).to.equal(1n) // Just default

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('30'))

      count = await issuanceAllocator.getTargetCount()
      expect(count).to.equal(2n) // Default + target1

      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target2, ethersLib.parseEther('20'))

      count = await issuanceAllocator.getTargetCount()
      expect(count).to.equal(3n) // Default + target1 + target2
    })

    it('should include default in getTargets array', async () => {
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('30'))

      const targets = await issuanceAllocator.getTargets()
      expect(targets.length).to.equal(2)
      expect(targets[0]).to.equal(ethersLib.ZeroAddress) // Default at index 0
      expect(targets[1]).to.equal(addresses.target1)
    })

    it('should return correct data for default target', async () => {
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('40'))

      const defaultAddress = await issuanceAllocator.getTargetAt(0)
      const data = await issuanceAllocator.getTargetData(defaultAddress)

      expect(data.allocatorMintingRate).to.equal(ethersLib.parseEther('60'))
      expect(data.selfMintingRate).to.equal(0n)
    })

    it('should report 100% total allocation when default is a real address', async () => {
      // Set target1 allocation first
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256)'](addresses.target1, ethersLib.parseEther('30'))

      // Change default to target2 (a real address, not address(0))
      await issuanceAllocator.connect(accounts.governor).setDefaultTarget(addresses.target2)

      // When default is a real address, it should report 100% total allocation
      const totalAllocation = await issuanceAllocator.getTotalAllocation()
      expect(totalAllocation.totalAllocationRate).to.equal(issuancePerBlock)
      expect(totalAllocation.allocatorMintingRate).to.equal(issuancePerBlock) // target1=30% + target2=70% = 100%
      expect(totalAllocation.selfMintingRate).to.equal(0n)
    })
  })
})

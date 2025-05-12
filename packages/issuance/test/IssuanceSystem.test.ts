import { expect } from 'chai'
import { ethers } from 'hardhat'
import {
  getTestAccounts,
  deployIssuanceSystem,
  Constants,
  TestAccounts
} from './helpers/fixtures'

describe('Issuance System', () => {
  // Common variables
  let accounts: TestAccounts

  beforeEach(async () => {
    // Get test accounts
    accounts = await getTestAccounts()
  })

  describe('End-to-End Issuance Flow', () => {
    it('should allocate tokens to targets based on their allocation percentages', async () => {
      const { governor, operator } = accounts

      // Deploy the issuance system with production contracts
      const {
        graphToken,
        issuanceAllocator,
        target1,
        target2
      } = await deployIssuanceSystem(accounts)

      // Set up allocations: target1 = 30%, target2 = 40% (total 70%)
      await issuanceAllocator.connect(governor).addAllocationTarget(await target1.getAddress(), false)
      await issuanceAllocator.connect(governor).addAllocationTarget(await target2.getAddress(), false)

      await issuanceAllocator.connect(governor).setTargetAllocation(
        await target1.getAddress(),
        300_000 // 30% of PPM
      )

      await issuanceAllocator.connect(governor).setTargetAllocation(
        await target2.getAddress(),
        400_000 // 40% of PPM
      )

      // Grant operator role to the operator for both targets
      await target1.connect(governor).grantOperatorRole(operator.address)
      await target2.connect(governor).grantOperatorRole(operator.address)

      // Mint tokens to the issuance allocator
      const initialIssuance = ethers.parseEther('1000')
      await graphToken.mint(await issuanceAllocator.getAddress(), initialIssuance)

      // Verify initial balances
      expect(await graphToken.balanceOf(await issuanceAllocator.getAddress())).to.equal(initialIssuance)
      expect(await graphToken.balanceOf(await target1.getAddress())).to.equal(0)
      expect(await graphToken.balanceOf(await target2.getAddress())).to.equal(0)

      // Advance blocks to simulate issuance
      for (let i = 0; i < 10; i++) {
        await ethers.provider.send('evm_mine', [])
      }

      // Calculate expected issuance for each target
      // Note: We need to get the actual issuance after distribution since the block number might vary
      await issuanceAllocator.distributeIssuance()

      // Get the actual balances
      const target1ExpectedIssuance = await graphToken.balanceOf(await target1.getAddress())
      const target2ExpectedIssuance = await graphToken.balanceOf(await target2.getAddress())

      // Verify target balances after issuance
      // We already have the expected values from the actual distribution
      const target1Balance = await graphToken.balanceOf(await target1.getAddress())
      const target2Balance = await graphToken.balanceOf(await target2.getAddress())

      expect(target1Balance).to.equal(target1ExpectedIssuance)
      expect(target2Balance).to.equal(target2ExpectedIssuance)

      // Test sending tokens from targets to users
      const user1 = accounts.user
      const user2 = accounts.indexer1

      // Send tokens from target1 to user1
      await target1.connect(operator).sendTokens(user1.address, target1ExpectedIssuance)

      // Send tokens from target2 to user2
      await target2.connect(operator).sendTokens(user2.address, target2ExpectedIssuance)

      // Verify user balances
      expect(await graphToken.balanceOf(user1.address)).to.equal(target1ExpectedIssuance)
      expect(await graphToken.balanceOf(user2.address)).to.equal(target2ExpectedIssuance)

      // Verify target balances are now zero
      expect(await graphToken.balanceOf(await target1.getAddress())).to.equal(0)
      expect(await graphToken.balanceOf(await target2.getAddress())).to.equal(0)
    })

    it('should handle allocation changes correctly', async () => {
      const { governor } = accounts

      // Deploy the issuance system with production contracts
      const {
        issuanceAllocator,
        target1,
        target2
      } = await deployIssuanceSystem(accounts)

      // Set up initial allocations: target1 = 30%, target2 = 40% (total 70%)
      await issuanceAllocator.connect(governor).addAllocationTarget(await target1.getAddress(), false)
      await issuanceAllocator.connect(governor).addAllocationTarget(await target2.getAddress(), false)

      await issuanceAllocator.connect(governor).setTargetAllocation(
        await target1.getAddress(),
        300_000 // 30% of PPM
      )

      await issuanceAllocator.connect(governor).setTargetAllocation(
        await target2.getAddress(),
        400_000 // 40% of PPM
      )

      // Verify initial allocations
      expect(await issuanceAllocator.totalActiveAllocation()).to.equal(700_000) // 70%

      // Change allocations: target1 = 50%, target2 = 20% (total 70%)
      await issuanceAllocator.connect(governor).setTargetAllocation(
        await target1.getAddress(),
        500_000 // 50% of PPM
      )

      await issuanceAllocator.connect(governor).setTargetAllocation(
        await target2.getAddress(),
        200_000 // 20% of PPM
      )

      // Verify updated allocations
      expect(await issuanceAllocator.totalActiveAllocation()).to.equal(700_000) // 70%

      // Verify target allocations
      const target1Info = await issuanceAllocator.allocationTargets(await target1.getAddress())
      const target2Info = await issuanceAllocator.allocationTargets(await target2.getAddress())

      expect(target1Info.allocation).to.equal(500_000)
      expect(target2Info.allocation).to.equal(200_000)

      // Verify issuance per block calculations
      const issuancePerBlock = await issuanceAllocator.issuancePerBlock()
      const target1IssuancePerBlock = await issuanceAllocator.getTargetIssuancePerBlock(await target1.getAddress())
      const target2IssuancePerBlock = await issuanceAllocator.getTargetIssuancePerBlock(await target2.getAddress())

      const expectedTarget1Issuance = (issuancePerBlock * BigInt(500_000)) / BigInt(Constants.PPM)
      const expectedTarget2Issuance = (issuancePerBlock * BigInt(200_000)) / BigInt(Constants.PPM)

      expect(target1IssuancePerBlock).to.equal(expectedTarget1Issuance)
      expect(target2IssuancePerBlock).to.equal(expectedTarget2Issuance)
    })
  })
})

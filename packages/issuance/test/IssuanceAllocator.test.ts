import { expect } from 'chai'
import { ethers } from 'hardhat'
import {
  getTestAccounts,
  deployTestGraphToken,
  deployIssuanceAllocator,
  deployDirectAllocation,
  Constants,
  TestAccounts
} from './helpers/fixtures'

// Role constants
const GOVERNOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GOVERNOR_ROLE"))

describe('IssuanceAllocator', () => {
  // Common variables
  let accounts: TestAccounts
  const issuancePerBlock = Constants.DEFAULT_ISSUANCE_PER_BLOCK

  // Test fixtures
  async function setupIssuanceAllocator() {
    // Deploy test GraphToken
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    // Deploy IssuanceAllocator with proxy
    const issuanceAllocator = await deployIssuanceAllocator(
      graphTokenAddress,
      accounts.governor,
      issuancePerBlock
    )

    // Deploy target contracts
    const target1 = await deployDirectAllocation(
      graphTokenAddress,
      accounts.governor
    )

    const target2 = await deployDirectAllocation(
      graphTokenAddress,
      accounts.governor
    )

    return { issuanceAllocator, graphToken, target1, target2 }
  }

  beforeEach(async () => {
    // Get test accounts
    accounts = await getTestAccounts()
  })

  describe('Initialization', () => {
    it('should set the governor role correctly', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()
      expect(await issuanceAllocator.hasRole(GOVERNOR_ROLE, accounts.governor.address)).to.be.true
    })

    it('should set the issuance per block correctly', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()
      expect(await issuanceAllocator.issuancePerBlock()).to.equal(issuancePerBlock)
    })
  })

  describe('Target Management', () => {
    it('should add allocation targets correctly', async () => {
      const { issuanceAllocator, target1, target2 } = await setupIssuanceAllocator()

      // Add targets
      await issuanceAllocator.connect(accounts.governor).addAllocationTarget(await target1.getAddress(), false)
      await issuanceAllocator.connect(accounts.governor).addAllocationTarget(await target2.getAddress(), false)

      // Verify targets were added
      const target1Info = await issuanceAllocator.allocationTargets(await target1.getAddress())
      const target2Info = await issuanceAllocator.allocationTargets(await target2.getAddress())

      expect(target1Info.exists).to.be.true
      expect(target2Info.exists).to.be.true
      expect(target1Info.isSelfMinter).to.be.false
      expect(target2Info.isSelfMinter).to.be.false
    })

    it('should revert when adding a target with address zero', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()
      await expect(issuanceAllocator.connect(accounts.governor).addAllocationTarget(ethers.ZeroAddress, false))
        .to.be.revertedWithCustomError(issuanceAllocator, 'TargetAddressCannotBeZero')
    })

    it('should revert when non-governor tries to add a target', async () => {
      const { issuanceAllocator, target1 } = await setupIssuanceAllocator()
      await expect(issuanceAllocator.connect(accounts.nonGovernor).addAllocationTarget(await target1.getAddress(), false))
        .to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')
    })

    it('should revert when adding a target that exists with different self-minter flag', async () => {
      const { issuanceAllocator, target1 } = await setupIssuanceAllocator()
      const targetAddress = await target1.getAddress()

      // Add as non-self-minting first
      await issuanceAllocator.connect(accounts.governor).addAllocationTarget(targetAddress, false)

      // Try to add again as self-minting
      await expect(issuanceAllocator.connect(accounts.governor).addAllocationTarget(targetAddress, true))
        .to.be.revertedWithCustomError(issuanceAllocator, 'TargetExistsWithDifferentSelfMinterFlag')
    })

    it('should set target allocations correctly', async () => {
      const { issuanceAllocator, target1, target2 } = await setupIssuanceAllocator()

      // Add targets
      await issuanceAllocator.connect(accounts.governor).addAllocationTarget(await target1.getAddress(), false)
      await issuanceAllocator.connect(accounts.governor).addAllocationTarget(await target2.getAddress(), false)

      // Set allocations
      await issuanceAllocator.connect(accounts.governor).setTargetAllocation(await target1.getAddress(), 300_000)
      await issuanceAllocator.connect(accounts.governor).setTargetAllocation(await target2.getAddress(), 400_000)

      // Verify allocations
      const target1Info = await issuanceAllocator.allocationTargets(await target1.getAddress())
      const target2Info = await issuanceAllocator.allocationTargets(await target2.getAddress())

      expect(target1Info.allocation).to.equal(300_000)
      expect(target2Info.allocation).to.equal(400_000)
      expect(await issuanceAllocator.totalActiveAllocation()).to.equal(700_000)
    })

    it('should revert when setting allocation for non-existent target', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()

      // Add targets
      await issuanceAllocator.connect(accounts.governor).addAllocationTarget(accounts.selfMintingTarget.address, true)

      const nonExistentTarget = accounts.nonGovernor.address
      await expect(issuanceAllocator.connect(accounts.governor).setTargetAllocation(nonExistentTarget, 500_000))
        .to.be.revertedWithCustomError(issuanceAllocator, 'TargetNotRegistered')
    })

    it('should revert when total allocation would exceed 100%', async () => {
      const { issuanceAllocator, target1, target2 } = await setupIssuanceAllocator()

      // Add targets
      await issuanceAllocator.connect(accounts.governor).addAllocationTarget(await target1.getAddress(), false)
      await issuanceAllocator.connect(accounts.governor).addAllocationTarget(await target2.getAddress(), false)

      // Set allocation for target1 to 60%
      await issuanceAllocator.connect(accounts.governor).setTargetAllocation(await target1.getAddress(), 600_000)

      // Try to set allocation for target2 to 50%, which would exceed 100%
      await expect(issuanceAllocator.connect(accounts.governor).setTargetAllocation(await target2.getAddress(), 500_000))
        .to.be.revertedWithCustomError(issuanceAllocator, 'InsufficientAllocationAvailable')
    })
  })

  describe('Issuance Rate Management', () => {
    it('should update issuance rate correctly', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()

      const newIssuancePerBlock = ethers.parseEther('200')
      await issuanceAllocator.connect(accounts.governor).setIssuancePerBlock(newIssuancePerBlock)

      expect(await issuanceAllocator.issuancePerBlock()).to.equal(newIssuancePerBlock)
    })

    it('should revert when non-governor tries to update issuance rate', async () => {
      const { issuanceAllocator } = await setupIssuanceAllocator()
      await expect(issuanceAllocator.connect(accounts.nonGovernor).setIssuancePerBlock(ethers.parseEther('200')))
        .to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')
    })
  })
})

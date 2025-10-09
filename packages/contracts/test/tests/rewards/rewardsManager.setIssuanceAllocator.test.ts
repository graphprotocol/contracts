import { RewardsManager } from '@graphprotocol/contracts'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { ethers } from 'hardhat'

import { NetworkFixture } from '../unit/lib/fixtures'

describe('RewardsManager setIssuanceAllocator ERC-165', () => {
  let fixture: NetworkFixture

  let rewardsManager: RewardsManager
  let governor: SignerWithAddress
  let indexer1: SignerWithAddress

  before(async function () {
    const signers = await ethers.getSigners()
    governor = signers[0]
    indexer1 = signers[1]

    fixture = new NetworkFixture(ethers.provider)
    const contracts = await fixture.load(governor)
    rewardsManager = contracts.RewardsManager
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('setIssuanceAllocator with ERC-165 checking', function () {
    it('should successfully set an issuance allocator that supports the interface', async function () {
      // Deploy a mock issuance allocator that supports ERC-165 and IIssuanceAllocator
      const MockIssuanceAllocatorFactory = await ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockAllocator = await MockIssuanceAllocatorFactory.deploy(ethers.utils.parseEther('50'))
      await mockAllocator.deployed()

      // Should succeed because MockIssuanceAllocator supports IIssuanceAllocator
      await expect(rewardsManager.connect(governor).setIssuanceAllocator(mockAllocator.address))
        .to.emit(rewardsManager, 'IssuanceAllocatorSet')
        .withArgs(ethers.constants.AddressZero, mockAllocator.address)

      // Verify the allocator was set
      expect(await rewardsManager.issuanceAllocator()).to.equal(mockAllocator.address)
    })

    it('should allow setting issuance allocator to zero address (disable)', async function () {
      // First set a valid allocator
      const MockIssuanceAllocatorFactory = await ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockAllocator = await MockIssuanceAllocatorFactory.deploy(ethers.utils.parseEther('50'))
      await mockAllocator.deployed()

      await rewardsManager.connect(governor).setIssuanceAllocator(mockAllocator.address)
      expect(await rewardsManager.issuanceAllocator()).to.equal(mockAllocator.address)

      // Now disable by setting to zero address
      await expect(rewardsManager.connect(governor).setIssuanceAllocator(ethers.constants.AddressZero))
        .to.emit(rewardsManager, 'IssuanceAllocatorSet')
        .withArgs(mockAllocator.address, ethers.constants.AddressZero)

      expect(await rewardsManager.issuanceAllocator()).to.equal(ethers.constants.AddressZero)
    })

    it('should revert when setting to EOA address (no contract code)', async function () {
      const eoaAddress = indexer1.address

      // Should revert because EOAs don't have contract code to call supportsInterface on
      await expect(rewardsManager.connect(governor).setIssuanceAllocator(eoaAddress)).to.be.reverted
    })

    it('should revert when setting to contract that does not support IIssuanceAllocator', async function () {
      // Deploy a contract that supports ERC-165 but not IIssuanceAllocator
      const MockERC165OnlyFactory = await ethers.getContractFactory(
        'contracts/tests/MockERC165OnlyContract.sol:MockERC165OnlyContract',
      )
      const erc165OnlyContract = await MockERC165OnlyFactory.deploy()
      await erc165OnlyContract.deployed()

      // Should revert because the contract doesn't support IIssuanceAllocator
      await expect(
        rewardsManager.connect(governor).setIssuanceAllocator(erc165OnlyContract.address),
      ).to.be.revertedWith('Contract does not support IIssuanceAllocator interface')
    })

    it('should not emit event when setting to same allocator address', async function () {
      // Deploy a mock issuance allocator
      const MockIssuanceAllocatorFactory = await ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockAllocator = await MockIssuanceAllocatorFactory.deploy(ethers.utils.parseEther('50'))
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

    it('should revert when called by non-governor', async function () {
      const MockIssuanceAllocatorFactory = await ethers.getContractFactory(
        'contracts/tests/MockIssuanceAllocator.sol:MockIssuanceAllocator',
      )
      const mockAllocator = await MockIssuanceAllocatorFactory.deploy(ethers.utils.parseEther('50'))
      await mockAllocator.deployed()

      // Should revert because indexer1 is not the governor
      await expect(rewardsManager.connect(indexer1).setIssuanceAllocator(mockAllocator.address)).to.be.revertedWith(
        'Only Controller governor',
      )
    })

    it('should validate interface before updating rewards calculation', async function () {
      // This test ensures that ERC165 validation happens before updateAccRewardsPerSignal
      // Deploy a contract that doesn't support IIssuanceAllocator
      const MockERC165OnlyFactory = await ethers.getContractFactory(
        'contracts/tests/MockERC165OnlyContract.sol:MockERC165OnlyContract',
      )
      const erc165OnlyContract = await MockERC165OnlyFactory.deploy()
      await erc165OnlyContract.deployed()

      // Should revert with interface error, not with any rewards calculation error
      await expect(
        rewardsManager.connect(governor).setIssuanceAllocator(erc165OnlyContract.address),
      ).to.be.revertedWith('Contract does not support IIssuanceAllocator interface')
    })
  })
})

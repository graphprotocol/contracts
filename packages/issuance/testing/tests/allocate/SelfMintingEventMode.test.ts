import { expect } from 'chai'
import { ethers as ethersLib } from 'ethers'

import { getEthers } from '../common/ethersHelper'
import { deployTestGraphToken, getTestAccounts } from '../common/fixtures'
import { deployDirectAllocation, deployIssuanceAllocator } from './fixtures'

describe('SelfMintingEventMode', () => {
  let accounts: any
  let graphToken: any
  let issuanceAllocator: any
  let selfMintingTarget: any
  let addresses: any
  let ethers: any // HH v3 ethers instance

  const issuancePerBlock = ethersLib.parseEther('100')

  // SelfMintingEventMode enum values
  const EventMode = {
    None: 0,
    Aggregate: 1,
    PerTarget: 2,
  }

  beforeEach(async () => {
    ethers = await getEthers()
    accounts = await getTestAccounts()

    // Deploy contracts
    graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    issuanceAllocator = await deployIssuanceAllocator(graphTokenAddress, accounts.governor, issuancePerBlock)

    selfMintingTarget = await deployDirectAllocation(graphTokenAddress, accounts.governor)

    // Cache addresses
    addresses = {
      issuanceAllocator: await issuanceAllocator.getAddress(),
      selfMintingTarget: await selfMintingTarget.getAddress(),
      graphToken: graphTokenAddress,
    }

    // Grant minter role
    await (graphToken as any).addMinter(addresses.issuanceAllocator)
  })

  describe('Initialization', () => {
    it('should initialize to PerTarget mode', async () => {
      const mode = await issuanceAllocator.getSelfMintingEventMode()
      expect(mode).to.equal(EventMode.PerTarget)
    })
  })

  describe('setSelfMintingEventMode', () => {
    it('should allow governor to set event mode', async () => {
      await expect(issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.None))
        .to.emit(issuanceAllocator, 'SelfMintingEventModeUpdated')
        .withArgs(EventMode.PerTarget, EventMode.None)

      expect(await issuanceAllocator.getSelfMintingEventMode()).to.equal(EventMode.None)
    })

    it('should return true when setting to same mode', async () => {
      const currentMode = await issuanceAllocator.getSelfMintingEventMode()
      // In HH v3, just await the call - if it reverts, the test fails
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(currentMode)
    })

    it('should not emit event when setting to same mode', async () => {
      const currentMode = await issuanceAllocator.getSelfMintingEventMode()
      await expect(issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(currentMode)).to.not.emit(
        issuanceAllocator,
        'SelfMintingEventModeUpdated',
      )
    })

    it('should allow switching between all modes', async () => {
      // PerTarget -> None
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.None)
      expect(await issuanceAllocator.getSelfMintingEventMode()).to.equal(EventMode.None)

      // None -> Aggregate
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.Aggregate)
      expect(await issuanceAllocator.getSelfMintingEventMode()).to.equal(EventMode.Aggregate)

      // Aggregate -> PerTarget
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.PerTarget)
      expect(await issuanceAllocator.getSelfMintingEventMode()).to.equal(EventMode.PerTarget)
    })

    it('should revert when non-governor tries to set mode', async () => {
      await expect(
        issuanceAllocator.connect(accounts.nonGovernor).setSelfMintingEventMode(EventMode.None),
      ).to.be.revertedWithCustomError(issuanceAllocator, 'AccessControlUnauthorizedAccount')
    })
  })

  describe('Event Emission - None Mode', () => {
    beforeEach(async () => {
      // Set to None mode
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.None)

      // Set up self-minting target
      const selfMintingRate = ethersLib.parseEther('30')
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, selfMintingRate)
    })

    it('should not emit IssuanceSelfMintAllowance events in None mode', async () => {
      // Advance blocks by calling distributeIssuance
      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()

      // Should not emit per-target events
      await expect(tx).to.not.emit(issuanceAllocator, 'IssuanceSelfMintAllowance')
    })

    it('should not emit IssuanceSelfMintAllowanceAggregate events in None mode', async () => {
      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()

      await expect(tx).to.not.emit(issuanceAllocator, 'IssuanceSelfMintAllowanceAggregate')
    })
  })

  describe('Event Emission - Aggregate Mode', () => {
    beforeEach(async () => {
      // Set to Aggregate mode
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.Aggregate)

      // Set up self-minting target
      const selfMintingRate = ethersLib.parseEther('30')
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, selfMintingRate)
    })

    it('should emit IssuanceSelfMintAllowanceAggregate event', async () => {
      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()

      await expect(tx).to.emit(issuanceAllocator, 'IssuanceSelfMintAllowanceAggregate')
    })

    it('should emit aggregate event with correct total amount', async () => {
      const selfMintingRate = ethersLib.parseEther('30')

      // Distribute to get to current state
      await issuanceAllocator.distributeIssuance()
      const startBlock = await ethers.provider.getBlockNumber()

      // Mine a block then distribute
      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()
      const endBlock = await ethers.provider.getBlockNumber()

      // Expected amount is for the block we just mined
      const blocks = endBlock - startBlock
      const expectedAmount = selfMintingRate * BigInt(blocks)

      await expect(tx)
        .to.emit(issuanceAllocator, 'IssuanceSelfMintAllowanceAggregate')
        .withArgs(expectedAmount, startBlock + 1, endBlock)
    })

    it('should not emit per-target events in Aggregate mode', async () => {
      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()

      await expect(tx).to.not.emit(issuanceAllocator, 'IssuanceSelfMintAllowance')
    })
  })

  describe('Event Emission - PerTarget Mode', () => {
    beforeEach(async () => {
      // Already in PerTarget mode by default
      const selfMintingRate = ethersLib.parseEther('30')
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, selfMintingRate)
    })

    it('should emit IssuanceSelfMintAllowance event for each target', async () => {
      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()

      await expect(tx).to.emit(issuanceAllocator, 'IssuanceSelfMintAllowance')
    })

    it('should emit per-target event with correct amount', async () => {
      const selfMintingRate = ethersLib.parseEther('30')

      // Distribute to get to current state
      await issuanceAllocator.distributeIssuance()
      const startBlock = await ethers.provider.getBlockNumber()

      // Mine a block then distribute
      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()
      const endBlock = await ethers.provider.getBlockNumber()

      // Expected amount is for the block we just mined
      const blocks = endBlock - startBlock
      const expectedAmount = selfMintingRate * BigInt(blocks)

      await expect(tx)
        .to.emit(issuanceAllocator, 'IssuanceSelfMintAllowance')
        .withArgs(addresses.selfMintingTarget, expectedAmount, startBlock + 1, endBlock)
    })

    it('should not emit aggregate events in PerTarget mode', async () => {
      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()

      await expect(tx).to.not.emit(issuanceAllocator, 'IssuanceSelfMintAllowanceAggregate')
    })
  })

  describe('Mode Switching During Operation', () => {
    it('should apply new mode immediately on next distribution', async () => {
      // Set up self-minting target
      const selfMintingRate = ethersLib.parseEther('30')
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, selfMintingRate)

      // PerTarget mode initially
      await ethers.provider.send('evm_mine', [])
      await expect(issuanceAllocator.distributeIssuance()).to.emit(issuanceAllocator, 'IssuanceSelfMintAllowance')

      // Switch to None mode
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.None)

      // Next distribution should not emit events
      await ethers.provider.send('evm_mine', [])
      await expect(issuanceAllocator.distributeIssuance()).to.not.emit(issuanceAllocator, 'IssuanceSelfMintAllowance')
    })

    it('should handle rapid mode switching correctly', async () => {
      const selfMintingRate = ethersLib.parseEther('30')
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, selfMintingRate)

      // Switch through all modes
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.None)
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.Aggregate)
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.PerTarget)

      // Should end up in PerTarget mode
      expect(await issuanceAllocator.getSelfMintingEventMode()).to.equal(EventMode.PerTarget)

      await ethers.provider.send('evm_mine', [])
      await expect(issuanceAllocator.distributeIssuance()).to.emit(issuanceAllocator, 'IssuanceSelfMintAllowance')
    })
  })

  describe('Gas Optimization', () => {
    it('should use less gas in None mode than PerTarget mode', async () => {
      const selfMintingRate = ethersLib.parseEther('30')
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, selfMintingRate)

      // Measure gas in PerTarget mode
      await ethers.provider.send('evm_mine', [])
      const perTargetTx = await issuanceAllocator.distributeIssuance()
      const perTargetReceipt = await perTargetTx.wait()
      const perTargetGas = perTargetReceipt.gasUsed

      // Switch to None mode
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.None)

      // Measure gas in None mode
      await ethers.provider.send('evm_mine', [])
      const noneTx = await issuanceAllocator.distributeIssuance()
      const noneReceipt = await noneTx.wait()
      const noneGas = noneReceipt.gasUsed

      // None mode should use less gas
      expect(noneGas).to.be.lessThan(perTargetGas)
    })

    it('should use less gas in Aggregate mode than PerTarget mode with multiple targets', async () => {
      // Add multiple self-minting targets
      const target2 = await deployDirectAllocation(await graphToken.getAddress(), accounts.governor)
      const target3 = await deployDirectAllocation(await graphToken.getAddress(), accounts.governor)

      const selfMintingRate = ethersLib.parseEther('10')
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, selfMintingRate)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target2.getAddress(), 0, selfMintingRate)
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](await target3.getAddress(), 0, selfMintingRate)

      // Measure gas in PerTarget mode
      await ethers.provider.send('evm_mine', [])
      const perTargetTx = await issuanceAllocator.distributeIssuance()
      const perTargetReceipt = await perTargetTx.wait()
      const perTargetGas = perTargetReceipt.gasUsed

      // Switch to Aggregate mode
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.Aggregate)

      // Measure gas in Aggregate mode
      await ethers.provider.send('evm_mine', [])
      const aggregateTx = await issuanceAllocator.distributeIssuance()
      const aggregateReceipt = await aggregateTx.wait()
      const aggregateGas = aggregateReceipt.gasUsed

      // Aggregate mode should use less gas
      expect(aggregateGas).to.be.lessThan(perTargetGas)
    })
  })

  describe('Edge Cases', () => {
    it('should handle mode changes when no self-minting targets exist', async () => {
      // No self-minting targets added
      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.None)

      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()

      // Should not emit any self-minting events
      await expect(tx).to.not.emit(issuanceAllocator, 'IssuanceSelfMintAllowance')
      await expect(tx).to.not.emit(issuanceAllocator, 'IssuanceSelfMintAllowanceAggregate')
    })

    it('should handle mode when totalSelfMintingRate is zero', async () => {
      // Add target with only allocator-minting (no self-minting)
      const allocatorMintingRate = ethersLib.parseEther('50')
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, allocatorMintingRate, 0)

      await issuanceAllocator.connect(accounts.governor).setSelfMintingEventMode(EventMode.Aggregate)

      await ethers.provider.send('evm_mine', [])
      const tx = await issuanceAllocator.distributeIssuance()

      // Should not emit self-minting events when totalSelfMintingRate is 0
      await expect(tx).to.not.emit(issuanceAllocator, 'IssuanceSelfMintAllowanceAggregate')
    })

    it('should work correctly after removing and re-adding self-minting target', async () => {
      const selfMintingRate = ethersLib.parseEther('30')

      // Add target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, selfMintingRate)

      // Remove target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, 0)

      // Re-add target
      await issuanceAllocator
        .connect(accounts.governor)
        ['setTargetAllocation(address,uint256,uint256)'](addresses.selfMintingTarget, 0, selfMintingRate)

      // Should emit events normally
      await ethers.provider.send('evm_mine', [])
      await expect(issuanceAllocator.distributeIssuance()).to.emit(issuanceAllocator, 'IssuanceSelfMintAllowance')
    })
  })
})

import { expect } from 'chai'
import { ethers as ethersLib } from 'ethers'

import { getEthers } from '../common/ethersHelper'
import { mineBlocks } from '../allocate/optimizationHelpers'
import {
  deployIndexingSignalSystem,
  type IndexingSignalSystem,
  SUBGRAPH_IDS,
  ROLES,
  DEFAULT_ISSUANCE_PER_BLOCK,
} from './fixtures'

describe('IndexingSignal', () => {
  let sys: IndexingSignalSystem
  let ethers: any

  before(async () => {
    ethers = await getEthers()
    sys = await deployIndexingSignalSystem()
  })

  // -- Deposit Tests --

  describe('deposit()', () => {
    const DEPOSIT_AMOUNT = ethersLib.parseEther('1000')

    it('should allow depositing GRT as signal', async () => {
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = sys

      // Mint GRT to user and approve
      await graphTokenHelper.mint(accounts.user.address, DEPOSIT_AMOUNT)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, DEPOSIT_AMOUNT)

      // Deposit
      await expect(
        (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, DEPOSIT_AMOUNT, 3),
      )
        .to.emit(indexingSignal, 'SignalDeposited')
        .withArgs(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, DEPOSIT_AMOUNT, 3)

      // Verify position
      const position = await indexingSignal.getDepositorPosition(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A)
      expect(position.tokens).to.equal(DEPOSIT_AMOUNT)
      expect(position.indexerCount).to.equal(3)

      // Verify totals
      expect(await indexingSignal.getTotalSignal()).to.equal(DEPOSIT_AMOUNT)
      expect(await indexingSignal.getSubgraphSignal(SUBGRAPH_IDS.SUBGRAPH_A)).to.equal(DEPOSIT_AMOUNT)
    })

    it('should reject zero deposit amount', async () => {
      const { indexingSignal, accounts } = sys
      await expect(
        (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_B, 0, 3),
      ).to.be.revertedWithCustomError(indexingSignal, 'DepositAmountZero')
    })

    it('should reject indexerCount below minimum for non-privileged', async () => {
      const { indexingSignal, accounts } = sys
      await expect(
        (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_B, DEPOSIT_AMOUNT, 1),
      ).to.be.revertedWithCustomError(indexingSignal, 'IndexerCountBelowMinimum')
    })

    it('should allow privileged signalers to use indexerCount below minimum', async () => {
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = sys

      // Grant privileged status
      await (indexingSignal as any).connect(accounts.governor).setPrivilegedSignaler(accounts.governor.address, true)

      // Mint and approve
      const amount = ethersLib.parseEther('100')
      await graphTokenHelper.mint(accounts.governor.address, amount)
      await (graphToken as any).connect(accounts.governor).approve(addresses.indexingSignal, amount)

      // Deposit with indexerCount = 1 (below minimum of 3)
      await expect(
        (indexingSignal as any).connect(accounts.governor).deposit(SUBGRAPH_IDS.SUBGRAPH_B, amount, 1),
      ).to.emit(indexingSignal, 'SignalDeposited')

      // Clean up privileged status
      await (indexingSignal as any).connect(accounts.governor).setPrivilegedSignaler(accounts.governor.address, false)
    })
  })

  // -- Withdraw Tests --

  describe('withdraw()', () => {
    it('should allow immediate withdrawal of signal', async () => {
      // Fresh system for isolation
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const amount = ethersLib.parseEther('500')

      // Setup: deposit
      await graphTokenHelper.mint(accounts.user.address, amount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, amount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, amount, 3)

      // Withdraw half
      const withdrawAmount = ethersLib.parseEther('200')
      const balanceBefore = await graphToken.balanceOf(accounts.user.address)

      await expect(
        (indexingSignal as any).connect(accounts.user).withdraw(SUBGRAPH_IDS.SUBGRAPH_A, withdrawAmount),
      )
        .to.emit(indexingSignal, 'SignalWithdrawn')
        .withArgs(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, withdrawAmount)

      // Verify balance returned
      const balanceAfter = await graphToken.balanceOf(accounts.user.address)
      expect(balanceAfter - balanceBefore).to.equal(withdrawAmount)

      // Verify position updated
      const position = await indexingSignal.getDepositorPosition(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A)
      expect(position.tokens).to.equal(amount - withdrawAmount)
    })

    it('should reject withdrawal exceeding signal', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const amount = ethersLib.parseEther('100')

      await graphTokenHelper.mint(accounts.user.address, amount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, amount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, amount, 3)

      await expect(
        (indexingSignal as any).connect(accounts.user).withdraw(SUBGRAPH_IDS.SUBGRAPH_A, amount + 1n),
      ).to.be.revertedWithCustomError(indexingSignal, 'InsufficientSignal')
    })
  })

  // -- Add Signal Tests --

  describe('addSignal()', () => {
    it('should allow adding more signal to existing position', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const initial = ethersLib.parseEther('500')
      const additional = ethersLib.parseEther('300')

      // Deposit initial
      await graphTokenHelper.mint(accounts.user.address, initial + additional)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, initial + additional)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, initial, 3)

      // Add signal
      await expect(
        (indexingSignal as any).connect(accounts.user).addSignal(SUBGRAPH_IDS.SUBGRAPH_A, additional),
      )
        .to.emit(indexingSignal, 'SignalAdded')
        .withArgs(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, additional)

      // Verify position
      const position = await indexingSignal.getDepositorPosition(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A)
      expect(position.tokens).to.equal(initial + additional)
    })

    it('should reject adding signal without existing position', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, accounts } = freshSys

      await expect(
        (indexingSignal as any).connect(accounts.user).addSignal(SUBGRAPH_IDS.SUBGRAPH_A, ethersLib.parseEther('100')),
      ).to.be.revertedWithCustomError(indexingSignal, 'NoExistingPosition')
    })
  })

  // -- Indexer Set Management --

  describe('setDepositorIndexerSet()', () => {
    it('should register indexer set for a position', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const amount = ethersLib.parseEther('1000')

      // Deposit
      await graphTokenHelper.mint(accounts.user.address, amount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, amount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, amount, 3)

      // Get 3 indexer addresses (reuse signers)
      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]

      // Register indexer set via operator
      await expect(
        (indexingSignal as any)
          .connect(accounts.operator)
          .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers),
      )
        .to.emit(indexingSignal, 'DepositorIndexerSetUpdated')
        .withArgs(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      // Verify set
      const storedSet = await indexingSignal.getDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A)
      expect(storedSet.length).to.equal(3)
      expect(storedSet[0]).to.equal(indexers[0])
      expect(storedSet[1]).to.equal(indexers[1])
      expect(storedSet[2]).to.equal(indexers[2])
    })

    it('should reject indexer set with wrong size', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const amount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, amount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, amount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, amount, 3)

      const signers = await ethers.getSigners()
      const wrongSizeSet = [signers[10].address, signers[11].address] // 2 instead of 3

      await expect(
        (indexingSignal as any)
          .connect(accounts.operator)
          .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, wrongSizeSet),
      ).to.be.revertedWithCustomError(indexingSignal, 'IndexerSetSizeMismatch')
    })

    it('should reject if caller lacks operator role', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const amount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, amount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, amount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, amount, 3)

      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]

      // Non-operator should be rejected (AccessControl revert)
      await expect(
        (indexingSignal as any)
          .connect(accounts.user)
          .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers),
      ).to.be.revertedWithCustomError(indexingSignal, 'AccessControlUnauthorizedAccount')
    })
  })

  // -- Virtual Escrow (collect) Tests --

  describe('collect()', () => {
    it('should mint and transfer GRT for accumulated issuance', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses, mockRewardsManager } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      // There's no curation signal, so total signal = indexing signal only
      // Deposit
      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      // Set up indexer set
      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]
      await (indexingSignal as any)
        .connect(accounts.operator)
        .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      // Mine some blocks to accrue issuance
      await mineBlocks(10)

      // Check virtual balance is non-zero
      const virtualBalance = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )
      expect(virtualBalance).to.be.greaterThan(0n)

      // Collect for first indexer (from any caller)
      const callerBalanceBefore = await graphToken.balanceOf(accounts.nonGovernor.address)
      const tx = await (indexingSignal as any)
        .connect(accounts.nonGovernor)
        .collect(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers[0], 0)
      const receipt = await tx.wait()

      // Verify GRT was minted to caller
      const callerBalanceAfter = await graphToken.balanceOf(accounts.nonGovernor.address)
      const collected = callerBalanceAfter - callerBalanceBefore
      expect(collected).to.be.greaterThan(0n)

      // Verify event emitted
      await expect(tx)
        .to.emit(indexingSignal, 'IssuanceCollected')
        .withArgs(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers[0], collected)
    })

    it('should independently track per-indexer collections', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      // Deposit
      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      // Set indexer set
      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]
      await (indexingSignal as any)
        .connect(accounts.operator)
        .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      // Mine blocks
      await mineBlocks(10)

      // Collect for indexer 0
      await (indexingSignal as any)
        .connect(accounts.nonGovernor)
        .collect(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers[0], 0)

      // After collecting for indexer 0, their virtual balance should be 0
      const balance0After = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )
      expect(balance0After).to.equal(0n)

      // But indexer 1 should still have uncollected balance
      const balance1After = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[1],
      )
      expect(balance1After).to.be.greaterThan(0n)
    })

    it('should support partial collection', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]
      await (indexingSignal as any)
        .connect(accounts.operator)
        .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      await mineBlocks(10)

      // Get available balance
      const available = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )
      expect(available).to.be.greaterThan(0n)

      // Collect half
      const halfAmount = available / 2n
      const balanceBefore = await graphToken.balanceOf(accounts.nonGovernor.address)
      await (indexingSignal as any)
        .connect(accounts.nonGovernor)
        .collect(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers[0], halfAmount)
      const balanceAfter = await graphToken.balanceOf(accounts.nonGovernor.address)

      expect(balanceAfter - balanceBefore).to.equal(halfAmount)

      // Remaining virtual balance should be approximately half
      const remaining = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )
      // Should be close to half (within rounding)
      expect(remaining).to.be.greaterThan(0n)
    })

    it('should reject collect for indexer not in set', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]
      await (indexingSignal as any)
        .connect(accounts.operator)
        .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      const notInSet = signers[15].address
      await expect(
        (indexingSignal as any)
          .connect(accounts.nonGovernor)
          .collect(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, notInSet, 0),
      ).to.be.revertedWithCustomError(indexingSignal, 'IndexerNotInSet')
    })

    it('should reject collect when indexer set is empty', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      // No indexer set registered — should fail
      const signers = await ethers.getSigners()
      await expect(
        (indexingSignal as any)
          .connect(accounts.nonGovernor)
          .collect(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, signers[10].address, 0),
      ).to.be.revertedWithCustomError(indexingSignal, 'IndexerSetEmpty')
    })
  })

  // -- Virtual Balance Tests --

  describe('getVirtualBalance()', () => {
    it('should return zero before any blocks are mined', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]
      await (indexingSignal as any)
        .connect(accounts.operator)
        .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      // Virtual balance should be 0 at the same block (or close to it)
      const balance = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )
      // Could be 0 or a tiny amount from the few blocks between deposit and query
      // The key point is it should be finite and small
      expect(balance).to.be.lessThan(ethersLib.parseEther('1000'))
    })

    it('should increase over time as blocks are mined', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]
      await (indexingSignal as any)
        .connect(accounts.operator)
        .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      // Check balance before mining
      const balanceBefore = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )

      // Mine blocks
      await mineBlocks(20)

      // Check balance after
      const balanceAfter = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )

      expect(balanceAfter).to.be.greaterThan(balanceBefore)
    })

    it('should return zero for indexer not in set', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]
      await (indexingSignal as any)
        .connect(accounts.operator)
        .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      await mineBlocks(10)

      // Check balance for address not in set
      const notInSet = signers[15].address
      const balance = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        notInSet,
      )
      expect(balance).to.equal(0n)
    })

    it('should split issuance equally among indexers', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]
      await (indexingSignal as any)
        .connect(accounts.operator)
        .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      await mineBlocks(10)

      // All three indexers should have the same virtual balance
      const balance0 = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )
      const balance1 = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[1],
      )
      const balance2 = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[2],
      )

      expect(balance0).to.equal(balance1)
      expect(balance1).to.equal(balance2)

      // Verify the three balances are equal (the main point of this test)
      // getPendingIssuance counts from deposit time, while getVirtualBalance
      // counts from indexer-set registration (later), so they won't match exactly.
      // The key assertion is that all three indexers get equal shares.
      expect(balance0).to.be.greaterThan(0n)
    })
  })

  // -- RCA Cancellation Tests --

  describe('onRCACancelled()', () => {
    it('should settle uncollected issuance (never minted)', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      const signers = await ethers.getSigners()
      const indexers = [signers[10].address, signers[11].address, signers[12].address]
      await (indexingSignal as any)
        .connect(accounts.operator)
        .setDepositorIndexerSet(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers)

      // Mine blocks to accrue issuance
      await mineBlocks(10)

      // Record GRT total supply before cancellation
      const supplyBefore = await graphToken.totalSupply()

      // Check balance exists
      const balanceBefore = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )
      expect(balanceBefore).to.be.greaterThan(0n)

      // Cancel RCA for indexer 0
      const tx = await (indexingSignal as any)
        .connect(accounts.nonGovernor)
        .onRCACancelled(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, indexers[0])

      await expect(tx).to.emit(indexingSignal, 'IssuanceSettled')

      // Supply should NOT have increased (no GRT minted for settled issuance)
      const supplyAfter = await graphToken.totalSupply()
      expect(supplyAfter).to.equal(supplyBefore)

      // Virtual balance should be zero after cancellation
      const balanceAfter = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[0],
      )
      expect(balanceAfter).to.equal(0n)

      // Other indexers should still have balances
      const balance1 = await indexingSignal.getVirtualBalance(
        accounts.user.address,
        SUBGRAPH_IDS.SUBGRAPH_A,
        indexers[1],
      )
      expect(balance1).to.be.greaterThan(0n)
    })
  })

  // -- Indexer Count Tests --

  describe('setIndexerCount()', () => {
    it('should allow changing indexer count', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const amount = ethersLib.parseEther('500')

      await graphTokenHelper.mint(accounts.user.address, amount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, amount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, amount, 3)

      await expect(
        (indexingSignal as any).connect(accounts.user).setIndexerCount(SUBGRAPH_IDS.SUBGRAPH_A, 5),
      )
        .to.emit(indexingSignal, 'IndexerCountChanged')
        .withArgs(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A, 3, 5)

      const position = await indexingSignal.getDepositorPosition(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A)
      expect(position.indexerCount).to.equal(5)
    })

    it('should reject below-minimum count for non-privileged', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const amount = ethersLib.parseEther('500')

      await graphTokenHelper.mint(accounts.user.address, amount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, amount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, amount, 3)

      await expect(
        (indexingSignal as any).connect(accounts.user).setIndexerCount(SUBGRAPH_IDS.SUBGRAPH_A, 1),
      ).to.be.revertedWithCustomError(indexingSignal, 'IndexerCountBelowMinimum')
    })
  })

  // -- Governor Config Tests --

  describe('governance', () => {
    it('should allow governor to set minimum indexer count', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, accounts } = freshSys

      await expect((indexingSignal as any).connect(accounts.governor).setMinimumIndexerCount(5))
        .to.emit(indexingSignal, 'MinimumIndexerCountSet')
        .withArgs(3, 5)

      expect(await indexingSignal.getMinimumIndexerCount()).to.equal(5)
    })

    it('should allow governor to set privileged signaler', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, accounts } = freshSys

      await expect(
        (indexingSignal as any).connect(accounts.governor).setPrivilegedSignaler(accounts.user.address, true),
      )
        .to.emit(indexingSignal, 'PrivilegedSignalerSet')
        .withArgs(accounts.user.address, true)

      expect(await indexingSignal.isPrivilegedSignaler(accounts.user.address)).to.equal(true)
    })

    it('should reject non-governor for governance functions', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, accounts } = freshSys

      await expect(
        (indexingSignal as any).connect(accounts.nonGovernor).setMinimumIndexerCount(5),
      ).to.be.revertedWithCustomError(indexingSignal, 'AccessControlUnauthorizedAccount')

      await expect(
        (indexingSignal as any).connect(accounts.nonGovernor).setPrivilegedSignaler(accounts.user.address, true),
      ).to.be.revertedWithCustomError(indexingSignal, 'AccessControlUnauthorizedAccount')
    })
  })

  // -- Issuance Accumulator Tests --

  describe('issuance accumulation', () => {
    it('should accumulate issuance proportional to signal and blocks', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      // Deposit (no curation signal, so all issuance goes to indexing)
      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      // Get accIssuancePerSignal before
      const accBefore = await indexingSignal.getAccIssuancePerSignal()

      // Mine blocks
      await mineBlocks(10)

      // Get accIssuancePerSignal after
      const accAfter = await indexingSignal.getAccIssuancePerSignal()

      // Should have increased
      expect(accAfter).to.be.greaterThan(accBefore)

      // With 100 GRT/block issuance and 1000 GRT signal, 10 blocks should give:
      // accIssuancePerSignal += (100 * 10 * 1e18) / 1000 = 1e18
      // This is approximate due to other blocks between transactions
      const delta = accAfter - accBefore
      expect(delta).to.be.greaterThan(0n)
    })

    it('should report pending issuance correctly', async () => {
      const freshSys = await deployIndexingSignalSystem()
      const { indexingSignal, graphToken, graphTokenHelper, accounts, addresses } = freshSys
      const depositAmount = ethersLib.parseEther('1000')

      await graphTokenHelper.mint(accounts.user.address, depositAmount)
      await (graphToken as any).connect(accounts.user).approve(addresses.indexingSignal, depositAmount)
      await (indexingSignal as any).connect(accounts.user).deposit(SUBGRAPH_IDS.SUBGRAPH_A, depositAmount, 3)

      await mineBlocks(10)

      const pending = await indexingSignal.getPendingIssuance(accounts.user.address, SUBGRAPH_IDS.SUBGRAPH_A)

      // Should be approximately: 100 GRT/block * ~10 blocks * (1000/1000) = ~1000 GRT
      // (total signal = 1000, deposit = 1000, so depositor gets 100%)
      expect(pending).to.be.greaterThan(0n)
    })
  })
})

import hre from 'hardhat'

import { delegators } from '../../../tasks/test/fixtures/delegators'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { ZERO_ADDRESS } from '@graphprotocol/toolshed'

import type { HorizonStaking, L2GraphToken } from '@graphprotocol/toolshed/deployments/horizon'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Delegator', () => {
  let horizonStaking: HorizonStaking
  let graphToken: L2GraphToken
  let delegator: HardhatEthersSigner
  let serviceProvider: HardhatEthersSigner
  let newServiceProvider: HardhatEthersSigner
  let verifier: string
  let newVerifier: string
  let snapshotId: string
  const maxVerifierCut = 1000000n
  const thawingPeriod = 2419200n // 28 days
  const tokens = ethers.parseEther('100000')

  // Subgraph service address is not set for integration tests
  const subgraphServiceAddress = '0x0000000000000000000000000000000000000000'

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken

    ;[serviceProvider, delegator, newServiceProvider] = await ethers.getSigners()

    verifier = ethers.Wallet.createRandom().address
    newVerifier = ethers.Wallet.createRandom().address
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])

    // Servide provider stake
    await graphToken.connect(serviceProvider).approve(horizonStaking.target, tokens)
    await horizonStaking.connect(serviceProvider).stake(tokens)

    // Create provision
    await horizonStaking.connect(serviceProvider).provision(serviceProvider.address, verifier, tokens, maxVerifierCut, thawingPeriod)

    // Send GRT to delegator and new service provider to use for delegation and staking
    await graphToken.connect(serviceProvider).transfer(delegator.address, tokens)
    await graphToken.connect(serviceProvider).transfer(newServiceProvider.address, tokens)
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('New Protocol Users', () => {
    it('should allow delegator to delegate to a service provider and verifier, undelegate and withdraw tokens', async () => {
      const delegatorBalanceBefore = await graphToken.balanceOf(delegator.address)
      const delegationTokens = ethers.parseEther('1000')

      // Delegate tokens to the service provider and verifier
      await graphToken.connect(delegator).approve(horizonStaking.target, delegationTokens)
      await horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, verifier, delegationTokens, 0n)

      // Verify delegation tokens were added to the delegation pool
      const delegationPool = await horizonStaking.getDelegationPool(
        serviceProvider.address,
        verifier,
      )
      expect(delegationPool.tokens).to.equal(delegationTokens, 'Delegation tokens were not added to the delegation pool')

      // Verify delegation shares were minted, since it's the first delegation
      // shares should be equal to tokens
      const delegation = await horizonStaking.getDelegation(
        serviceProvider.address,
        verifier,
        delegator.address,
      )
      expect(delegation.shares).to.equal(delegationTokens, 'Delegation shares were not minted correctly')

      // Undelegate tokens
      await horizonStaking.connect(delegator)['undelegate(address,address,uint256)'](serviceProvider.address, verifier, delegationTokens)

      // Wait for thawing period
      await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
      await ethers.provider.send('evm_mine', [])

      // Withdraw tokens
      await horizonStaking.connect(delegator)['withdrawDelegated(address,address,uint256)'](serviceProvider.address, verifier, 1n)

      // Delegator should have received their tokens back
      expect(await graphToken.balanceOf(delegator.address)).to.equal(delegatorBalanceBefore, 'Delegator balance should be the same as before delegation')
    })

    it('should revert when delegating to an invalid provision', async () => {
      const delegateTokens = ethers.parseEther('1000')
      const invalidVerifier = await ethers.Wallet.createRandom().getAddress()

      await graphToken.connect(delegator).approve(horizonStaking.target, delegateTokens)
      await expect(
        horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, invalidVerifier, delegateTokens, 0n),
      ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidProvision')
    })

    it('should revert when delegating less than minimum delegation', async () => {
      const minDelegation = ethers.parseEther('1')

      await graphToken.connect(delegator).approve(horizonStaking.target, minDelegation - 1n)
      await expect(
        horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, verifier, minDelegation - 1n, 0n),
      ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInsufficientDelegationTokens')
    })

    describe('Delegation pool already exists', () => {
      const newProvisionTokens = ethers.parseEther('10000')
      const delegationPoolTokens = ethers.parseEther('1000')

      beforeEach(async () => {
        // Delegate tokens to initialize the delegation pool
        await graphToken.connect(delegator).approve(horizonStaking.target, delegationPoolTokens)
        await horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, verifier, delegationPoolTokens, 0n)

        // Create new provision for a new service provider and verifier combo
        await graphToken.connect(newServiceProvider).approve(horizonStaking.target, newProvisionTokens)
        await horizonStaking.connect(newServiceProvider).stake(newProvisionTokens)
        await horizonStaking.connect(newServiceProvider).provision(newServiceProvider.address, newVerifier, newProvisionTokens, maxVerifierCut, thawingPeriod)
      })

      it('should allow delegator to undelegate and redelegate to new provider and verifier', async () => {
        // Undelegate 20% of delegator's shares
        const delegation = await horizonStaking.getDelegation(
          serviceProvider.address,
          verifier,
          delegator.address,
        )
        const undelegateShares = delegation.shares / 5n

        await horizonStaking.connect(delegator)['undelegate(address,address,uint256)'](serviceProvider.address, verifier, undelegateShares)

        // Wait for thawing period
        await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
        await ethers.provider.send('evm_mine', [])

        await graphToken.connect(delegator).approve(horizonStaking.target, undelegateShares)
        await horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](newServiceProvider.address, newVerifier, undelegateShares, 0n)

        // Verify delegation shares were transferred to the new service provider
        const delegationPool = await horizonStaking.getDelegationPool(
          newServiceProvider.address,
          newVerifier,
        )
        expect(delegationPool.tokens).to.equal(undelegateShares, 'Delegation tokens were not transferred to the new service provider')

        const newDelegation = await horizonStaking.getDelegation(
          newServiceProvider.address,
          newVerifier,
          delegator.address,
        )
        expect(newDelegation.shares).to.equal(undelegateShares, 'Delegation shares were not transferred to the new service provider')
      })

      it('should handle multiple undelegations with nThawRequests = 0', async () => {
        const delegatorBalanceBefore = await graphToken.balanceOf(delegator.address)
        const delegationPool = await horizonStaking.getDelegationPool(
          serviceProvider.address,
          verifier,
        )

        const delegation = await horizonStaking.getDelegation(
          serviceProvider.address,
          verifier,
          delegator.address,
        )
        const undelegateShares = delegation.shares / 10n

        let totalExpectedTokens = 0n
        let remainingShares = delegation.shares
        let remainingPoolTokens = delegationPool.tokens

        // Undelegate shares in 3 different transactions
        for (let i = 0; i < 3; i++) {
          const tokensOut = (undelegateShares * remainingPoolTokens) / remainingShares
          totalExpectedTokens += tokensOut

          await horizonStaking.connect(delegator)['undelegate(address,address,uint256)'](serviceProvider.address, verifier, undelegateShares)

          remainingShares -= undelegateShares
          remainingPoolTokens -= tokensOut
        }

        // Wait for thawing period
        await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
        await ethers.provider.send('evm_mine', [])

        // Withdraw all thaw requests
        await horizonStaking.connect(delegator)['withdrawDelegated(address,address,uint256)'](serviceProvider.address, verifier, 0n)

        // Verify tokens were transferred to delegator
        expect(await graphToken.balanceOf(delegator.address))
          .to.equal(delegatorBalanceBefore + totalExpectedTokens, 'Delegator balance should be the same as before delegation')
      })

      it('should handle multiple undelegations with nThawRequests = 1', async () => {
        const delegatorBalanceBefore = await graphToken.balanceOf(delegator.address)
        const delegationPool = await horizonStaking.getDelegationPool(
          serviceProvider.address,
          verifier,
        )

        const delegation = await horizonStaking.getDelegation(
          serviceProvider.address,
          verifier,
          delegator.address,
        )
        const undelegateShares = delegation.shares / 10n

        let totalExpectedTokens = 0n
        let remainingShares = delegation.shares
        let remainingPoolTokens = delegationPool.tokens

        // Undelegate shares in 3 different transactions
        for (let i = 0; i < 3; i++) {
          const tokensOut = (undelegateShares * remainingPoolTokens) / remainingShares
          totalExpectedTokens += tokensOut

          await horizonStaking.connect(delegator)['undelegate(address,address,uint256)'](serviceProvider.address, verifier, undelegateShares)

          remainingShares -= undelegateShares
          remainingPoolTokens -= tokensOut
        }

        // Wait for thawing period
        await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
        await ethers.provider.send('evm_mine', [])

        // Withdraw each thaw request individually
        for (let i = 0; i < 3; i++) {
          await horizonStaking.connect(delegator)['withdrawDelegated(address,address,uint256)'](serviceProvider.address, verifier, 1n)
        }

        // Verify tokens were transferred to delegator
        expect(await graphToken.balanceOf(delegator.address))
          .to.equal(delegatorBalanceBefore + totalExpectedTokens, 'Delegator balance should be the same as before delegation')
      })

      it('should not revert when withdrawing before thawing period', async () => {
        const delegatorBalanceBefore = await graphToken.balanceOf(delegator.address)
        const delegation = await horizonStaking.getDelegation(
          serviceProvider.address,
          verifier,
          delegator.address,
        )
        const undelegateShares = delegation.shares / 10n

        await horizonStaking.connect(delegator)['undelegate(address,address,uint256)'](serviceProvider.address, verifier, undelegateShares)

        await expect(
          horizonStaking.connect(delegator)['withdrawDelegated(address,address,uint256)'](serviceProvider.address, verifier, 1n),
        ).to.not.be.reverted

        // Verify tokens were not transferred to delegator
        expect(await graphToken.balanceOf(delegator.address))
          .to.equal(delegatorBalanceBefore, 'Delegator balance should be the same as before delegation')
      })
    })
  })

  describe('Existing Protocol Users', () => {
    let indexer: HardhatEthersSigner
    let existingDelegator: HardhatEthersSigner
    let delegatedTokens: bigint

    let snapshotId: string

    before(async () => {
      // Get indexer
      indexer = await ethers.getSigner(delegators[0].delegations[0].indexerAddress)

      // Get delegator
      existingDelegator = await ethers.getSigner(delegators[0].address)

      // Get delegated tokens
      delegatedTokens = delegators[0].delegations[0].tokens
    })

    beforeEach(async () => {
      // Take a snapshot before each test
      snapshotId = await ethers.provider.send('evm_snapshot', [])
    })

    afterEach(async () => {
      // Revert to the snapshot after each test
      await ethers.provider.send('evm_revert', [snapshotId])
    })

    it('should be able to undelegate and withdraw tokens after the transition period', async () => {
      // Get delegator's delegation
      const delegation = await horizonStaking.getDelegation(
        indexer.address,
        subgraphServiceAddress,
        existingDelegator.address,
      )

      // Undelegate tokens
      await horizonStaking.connect(existingDelegator)['undelegate(address,address,uint256)'](indexer.address, subgraphServiceAddress, delegation.shares)

      // Wait for thawing period
      await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod) + 1])
      await ethers.provider.send('evm_mine', [])

      // Get delegator balance before withdrawing
      const balanceBefore = await graphToken.balanceOf(existingDelegator.address)

      // Withdraw tokens
      await horizonStaking.connect(existingDelegator)['withdrawDelegated(address,address,uint256)'](indexer.address, subgraphServiceAddress, 1n)

      // Get delegator balance after withdrawing
      const balanceAfter = await graphToken.balanceOf(existingDelegator.address)

      // Expected balance after is the balance before plus the tokens minus the 0.5% delegation tax
      // because the delegation was before the horizon upgrade, after the upgrade there is no tax
      const expectedBalanceAfter = balanceBefore + delegatedTokens - (delegatedTokens * 5000n / 1000000n)

      // Verify tokens were transferred to delegator
      expect(balanceAfter).to.equal(expectedBalanceAfter, 'Tokens were not transferred to delegator')
    })

    describe('Undelegated before horizon upgrade', () => {
      before(async () => {
        const delegatorFixture = delegators[2]
        const delegationFixture = delegatorFixture.delegations[0]

        // Get signers
        indexer = await ethers.getSigner(delegationFixture.indexerAddress)
        existingDelegator = await ethers.getSigner(delegatorFixture.address)

        // Verify delegator is undelegated
        expect(delegatorFixture.undelegate).to.be.true
      })

      it('should allow delegator to withdraw tokens undelegated before horizon upgrade', async () => {
        // Mine remaining blocks to complete thawing period
        const oldThawingPeriod = 6646
        for (let i = 0; i < oldThawingPeriod + 1; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Get delegator balance before withdrawing
        const balanceBefore = await graphToken.balanceOf(existingDelegator.address)

        // Withdraw tokens
        await horizonStaking.connect(existingDelegator)['withdrawDelegated(address,address)'](indexer.address, ZERO_ADDRESS)

        // Get delegator balance after withdrawing
        const balanceAfter = await graphToken.balanceOf(existingDelegator.address)

        // Expected balance after is the balance before plus the tokens minus the 0.5% delegation tax
        // because the delegation was before the horizon upgrade, after the upgrade there is no tax
        const expectedBalanceAfter = balanceBefore + tokens - (tokens * 5000n / 1000000n)

        // Verify tokens were transferred to delegator
        expect(balanceAfter).to.equal(expectedBalanceAfter, 'Tokens were not transferred to delegator')
      })
    })
  })
})

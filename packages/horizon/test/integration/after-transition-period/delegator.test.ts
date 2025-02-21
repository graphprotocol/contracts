import hre from 'hardhat'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import {
  createProvision,
  delegate,
  redelegate,
  stake,
  undelegate,
  withdrawDelegated,
} from '../shared/staking'

describe('Delegator (after transition period)', () => {
  let horizonStaking: HorizonStaking
  let graphToken: IGraphToken
  let delegator: SignerWithAddress
  let serviceProvider: SignerWithAddress
  let newServiceProvider: SignerWithAddress
  let verifier: string
  let newVerifier: string

  const maxVerifierCut = 1000000
  const thawingPeriod = 2419200 // 28 days
  const tokens = ethers.parseEther('100000')

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken

    [serviceProvider, delegator, newServiceProvider] = await ethers.getSigners()

    verifier = await ethers.Wallet.createRandom().getAddress()
    newVerifier = await ethers.Wallet.createRandom().getAddress()

    // Servide provider stake
    await stake({ horizonStaking, graphToken, serviceProvider, tokens })

    // Create provision
    await createProvision({
      horizonStaking,
      serviceProvider,
      verifier,
      tokens,
      maxVerifierCut,
      thawingPeriod,
    })

    // Send funds to delegator and new service provider
    await graphToken.connect(serviceProvider).transfer(delegator.address, tokens)
    await graphToken.connect(serviceProvider).transfer(newServiceProvider.address, tokens)
  })

  it('should allow delegator to delegate to a service provider and verifier, undelegate and withdraw tokens', async () => {
    const delegatorBalanceBefore = await graphToken.balanceOf(delegator.address)
    const delegationTokens = ethers.parseEther('1000')

    // Delegate tokens to the service provider and verifier
    await delegate({
      horizonStaking,
      graphToken,
      delegator,
      serviceProvider,
      verifier,
      tokens: delegationTokens,
      minSharesOut: 0n,
    })

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
    await undelegate({
      horizonStaking,
      delegator,
      serviceProvider,
      verifier,
      shares: delegationTokens,
    })

    // Wait for thawing period
    await ethers.provider.send('evm_increaseTime', [thawingPeriod])
    await ethers.provider.send('evm_mine', [])

    // Withdraw tokens
    await withdrawDelegated({
      horizonStaking,
      delegator,
      serviceProvider,
      verifier,
      nThawRequests: BigInt(1),
    })

    // Delegator should have received their tokens back
    expect(await graphToken.balanceOf(delegator.address)).to.equal(delegatorBalanceBefore, 'Delegator balance should be the same as before delegation')
  })

  it('should revert when delegating to an invalid provision', async () => {
    const delegateTokens = ethers.parseEther('1000')
    const invalidVerifier = await ethers.Wallet.createRandom().getAddress()

    await expect(
      delegate({
        horizonStaking,
        graphToken,
        delegator,
        serviceProvider,
        verifier: invalidVerifier,
        tokens: delegateTokens,
        minSharesOut: 0n,
      }),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidProvision')
  })

  it('should revert when delegating less than minimum delegation', async () => {
    const minDelegation = ethers.parseEther('1')

    await expect(
      delegate({
        horizonStaking,
        graphToken,
        delegator,
        serviceProvider,
        verifier,
        tokens: minDelegation - 1n,
        minSharesOut: 0n,
      }),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInsufficientDelegationTokens')
  })

  describe('Delegation pool already exists', () => {
    const newProvisionTokens = ethers.parseEther('10000')
    const delegationPoolTokens = ethers.parseEther('1000')

    before(async () => {
      // Delegate tokens to initialize the delegation pool
      await delegate({
        horizonStaking,
        graphToken,
        delegator,
        serviceProvider,
        verifier,
        tokens: delegationPoolTokens,
        minSharesOut: 0n,
      })

      // Create new provision for a new service provider and verifier combo
      await stake({
        horizonStaking,
        graphToken,
        serviceProvider: newServiceProvider,
        tokens: newProvisionTokens,
      })
      await createProvision({
        horizonStaking,
        serviceProvider: newServiceProvider,
        verifier: newVerifier,
        tokens: newProvisionTokens,
        maxVerifierCut,
        thawingPeriod,
      })
    })

    it('should allow delegator to undelegate and redelegate to new provider and verifier', async () => {
      // Undelegate 20% of delegator's shares
      const delegation = await horizonStaking.getDelegation(
        serviceProvider.address,
        verifier,
        delegator.address,
      )
      const undelegateShares = delegation.shares / 5n

      await undelegate({
        horizonStaking,
        delegator,
        serviceProvider,
        verifier,
        shares: undelegateShares,
      })

      // Wait for thawing period
      await ethers.provider.send('evm_increaseTime', [thawingPeriod])
      await ethers.provider.send('evm_mine', [])

      await redelegate({
        horizonStaking,
        delegator,
        serviceProvider,
        verifier,
        newServiceProvider,
        newVerifier,
        minSharesForNewProvider: 0n,
        nThawRequests: BigInt(1),
      })

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

        await undelegate({
          horizonStaking,
          delegator,
          serviceProvider,
          verifier,
          shares: undelegateShares,
        })

        remainingShares -= undelegateShares
        remainingPoolTokens -= tokensOut
      }

      // Wait for thawing period
      await ethers.provider.send('evm_increaseTime', [thawingPeriod])
      await ethers.provider.send('evm_mine', [])

      // Withdraw all thaw requests
      await withdrawDelegated({
        horizonStaking,
        delegator,
        serviceProvider,
        verifier,
        nThawRequests: BigInt(0), // Withdraw all
      })

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

        await undelegate({
          horizonStaking,
          delegator,
          serviceProvider,
          verifier,
          shares: undelegateShares,
        })

        remainingShares -= undelegateShares
        remainingPoolTokens -= tokensOut
      }

      // Wait for thawing period
      await ethers.provider.send('evm_increaseTime', [thawingPeriod])
      await ethers.provider.send('evm_mine', [])

      // Withdraw each thaw request individually
      for (let i = 0; i < 3; i++) {
        await withdrawDelegated({
          horizonStaking,
          delegator,
          serviceProvider,
          verifier,
          nThawRequests: BigInt(1), // Withdraw one thaw request at a time
        })
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

      await undelegate({
        horizonStaking,
        delegator,
        serviceProvider,
        verifier,
        shares: undelegateShares,
      })

      await expect(
        withdrawDelegated({
          horizonStaking,
          delegator,
          serviceProvider,
          verifier,
          nThawRequests: BigInt(1),
        }),
      ).to.not.be.reverted

      // Verify tokens were not transferred to delegator
      expect(await graphToken.balanceOf(delegator.address))
        .to.equal(delegatorBalanceBefore, 'Delegator balance should be the same as before delegation')
    })
  })
})

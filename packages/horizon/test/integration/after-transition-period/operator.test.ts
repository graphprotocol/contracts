import hre from 'hardhat'

import { ethers } from 'hardhat'
import { expect } from 'chai'
import { ONE_MILLION } from '@graphprotocol/toolshed'
import { PaymentTypes } from '@graphprotocol/toolshed/deployments/horizon'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'

import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Operator', () => {
  let serviceProvider: HardhatEthersSigner
  let verifier: string
  let operator: HardhatEthersSigner

  const tokens = ethers.parseEther('100000')
  const maxVerifierCut = 1000000n // 100%
  const thawingPeriod = 2419200n

  const graph = hre.graph()
  const { stakeTo } = graph.horizon.actions
  const horizonStaking = graph.horizon.contracts.HorizonStaking
  const graphToken = graph.horizon.contracts.L2GraphToken

  before(async () => {
    // Get signers
    [serviceProvider, operator] = await ethers.getSigners()
    verifier = await ethers.Wallet.createRandom().getAddress()
    await setGRTBalance(graph.provider, graphToken.target, operator.address, ONE_MILLION)

    // Authorize operator for verifier
    await horizonStaking.connect(serviceProvider).setOperator(verifier, operator.address, true)

    // Fund operator with tokens
    await graphToken.connect(serviceProvider).transfer(operator.address, tokens)
  })

  it('operator stakes using stakeTo and service provider unstakes', async () => {
    const stakeTokens = ethers.parseEther('100')
    const operatorBalanceBefore = await graphToken.balanceOf(operator.address)
    const serviceProviderBalanceBefore = await graphToken.balanceOf(serviceProvider.address)

    // Operator stakes on behalf of service provider
    await stakeTo(operator, [serviceProvider.address, stakeTokens])

    // Service provider unstakes
    await horizonStaking.connect(serviceProvider).unstake(stakeTokens)

    // Verify tokens were removed from operator's address
    const operatorBalanceAfter = await graphToken.balanceOf(operator.address)
    expect(operatorBalanceAfter).to.be.equal(operatorBalanceBefore - stakeTokens)

    // Verify tokens were added to service provider's address
    const serviceProviderBalanceAfter = await graphToken.balanceOf(serviceProvider.address)
    expect(serviceProviderBalanceAfter).to.be.equal(serviceProviderBalanceBefore + stakeTokens)
  })

  it('operator sets delegation fee cut', async () => {
    const feeCut = 100000 // 10%
    const paymentType = PaymentTypes.QueryFee

    // Operator sets delegation fee cut
    await horizonStaking.connect(operator).setDelegationFeeCut(
      serviceProvider.address,
      verifier,
      paymentType,
      feeCut,
    )

    // Verify fee cut
    const delegationFeeCut = await horizonStaking.getDelegationFeeCut(
      serviceProvider.address,
      verifier,
      paymentType,
    )
    expect(delegationFeeCut).to.equal(feeCut)
  })

  describe('Provision', () => {
    before(async () => {
      const provisionTokens = ethers.parseEther('10000')
      // Operator stakes tokens to service provider
      await stakeTo(operator, [serviceProvider.address, provisionTokens])

      // Operator creates provision
      await horizonStaking.connect(serviceProvider).provision(serviceProvider.address, verifier, provisionTokens, maxVerifierCut, thawingPeriod)

      // Verify provision
      const provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
      expect(provision.tokens).to.equal(provisionTokens)
    })

    it('operator thaws and deprovisions', async () => {
      const thawTokens = ethers.parseEther('100')
      const idleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
      const provisionTokensBefore = (await horizonStaking.getProvision(serviceProvider.address, verifier)).tokens

      // Operator thaws tokens
      await horizonStaking.connect(serviceProvider).thaw(serviceProvider.address, verifier, thawTokens)

      // Increase time
      await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
      await ethers.provider.send('evm_mine', [])

      // Operator deprovisions
      await horizonStaking.connect(serviceProvider).deprovision(serviceProvider.address, verifier, 1n)

      // Verify idle stake increased by thawed tokens
      const idleStakeAfter = await horizonStaking.getIdleStake(serviceProvider.address)
      expect(idleStakeAfter).to.equal(idleStakeBefore + thawTokens)

      // Verify provision tokens decreased by thawed tokens
      const provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
      expect(provision.tokens).to.equal(provisionTokensBefore - thawTokens)
    })

    it('operator thaws and reprovisions', async () => {
      const thawTokens = ethers.parseEther('100')

      // Operator thaws tokens
      await horizonStaking.connect(serviceProvider).thaw(serviceProvider.address, verifier, thawTokens)

      // Increase time
      await ethers.provider.send('evm_increaseTime', [Number(thawingPeriod)])
      await ethers.provider.send('evm_mine', [])

      // Create new verifier and authorize operator
      const newVerifier = await ethers.Wallet.createRandom().getAddress()
      await horizonStaking.connect(serviceProvider).setOperator(newVerifier, operator.address, true)

      // Operator creates a provision for the new verifier
      await horizonStaking.connect(serviceProvider).provision(serviceProvider.address, newVerifier, thawTokens, maxVerifierCut, thawingPeriod)

      // Operator reprovisions
      await horizonStaking.connect(serviceProvider).reprovision(serviceProvider.address, verifier, newVerifier, 1n)
    })

    it('operator sets provision parameters', async () => {
      const newMaxVerifierCut = 500000 // 50%
      const newThawingPeriod = 7200 // 2 hours

      // Operator sets new parameters
      await horizonStaking.connect(operator).setProvisionParameters(
        serviceProvider.address,
        verifier,
        newMaxVerifierCut,
        newThawingPeriod,
      )

      // Verify new parameters
      const provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
      expect(provision.maxVerifierCutPending).to.equal(newMaxVerifierCut)
      expect(provision.thawingPeriodPending).to.equal(newThawingPeriod)
    })
  })
})

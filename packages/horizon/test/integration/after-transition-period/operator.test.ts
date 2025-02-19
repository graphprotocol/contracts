import hre from 'hardhat'
import { expect } from 'chai'
import { ethers } from 'hardhat'
import { HorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { createProvision, deprovision, reprovision, stakeTo, thaw, unstake } from '../shared/staking'
import { PaymentTypes } from '../utils/types'

describe('Operator', () => {
  let horizonStaking: HorizonStaking
  let graphToken: IGraphToken
  let serviceProvider: SignerWithAddress
  let verifier: string
  let operator: SignerWithAddress

  const tokens = ethers.parseEther('100000')
  const maxVerifierCut = 1000000 // 100%
  const thawingPeriod = 2419200

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken

    // Get signers
    [serviceProvider, operator] = await ethers.getSigners()
    verifier = await ethers.Wallet.createRandom().getAddress()

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
    await stakeTo(horizonStaking, graphToken, operator, serviceProvider, stakeTokens)

    // Service provider unstakes
    await unstake(horizonStaking, serviceProvider, stakeTokens)

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
      await stakeTo(horizonStaking, graphToken, operator, serviceProvider, provisionTokens)

      // Operator creates provision
      await createProvision({
        horizonStaking,
        serviceProvider,
        verifier,
        tokens: provisionTokens,
        maxVerifierCut,
        thawingPeriod,
        signer: operator,
      })

      // Verify provision
      const provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
      expect(provision.tokens).to.equal(provisionTokens)
    })

    it('operator thaws and deprovisions', async () => {
      const thawTokens = ethers.parseEther('100')
      const idleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
      const provisionTokensBefore = (await horizonStaking.getProvision(serviceProvider.address, verifier)).tokens

      // Operator thaws tokens
      await thaw({
        horizonStaking,
        serviceProvider,
        verifier,
        tokens: thawTokens,
        signer: operator,
      })

      // Increase time
      await ethers.provider.send('evm_increaseTime', [thawingPeriod])
      await ethers.provider.send('evm_mine', [])

      // Operator deprovisions
      await deprovision({
        horizonStaking,
        serviceProvider,
        verifier,
        nThawRequests: 1n,
        signer: operator,
      })

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
      await thaw({
        horizonStaking,
        serviceProvider,
        verifier,
        tokens: thawTokens,
        signer: operator,
      })

      // Increase time
      await ethers.provider.send('evm_increaseTime', [thawingPeriod])
      await ethers.provider.send('evm_mine', [])

      // Create new verifier and authorize operator
      const newVerifier = await ethers.Wallet.createRandom().getAddress()
      await horizonStaking.connect(serviceProvider).setOperator(newVerifier, operator.address, true)

      // Operator creates a provision for the new verifier
      await createProvision({
        horizonStaking,
        serviceProvider,
        verifier: newVerifier,
        tokens: thawTokens,
        maxVerifierCut,
        thawingPeriod,
        signer: operator,
      })

      // Operator reprovisions
      await reprovision({
        horizonStaking,
        serviceProvider,
        verifier,
        newVerifier,
        nThawRequests: 1n,
        signer: operator,
      })
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

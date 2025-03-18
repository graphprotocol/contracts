import hre from 'hardhat'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HDNodeWallet } from 'ethers'
import { IHorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import {
  createProvision,
  delegate,
  slash,
  stake,
  thaw,
} from '../shared/staking'

describe('Slasher', () => {
  let horizonStaking: IHorizonStaking
  let graphToken: IGraphToken
  let serviceProvider: SignerWithAddress
  let delegator: SignerWithAddress
  let verifier: HDNodeWallet
  let verifierDestination: string

  const maxVerifierCut = 1000000 // 100%
  const thawingPeriod = 2419200 // 28 days
  const provisionTokens = ethers.parseEther('10000')
  const delegationTokens = ethers.parseEther('1000')

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking as unknown as IHorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken

    [serviceProvider, delegator] = await ethers.getSigners()
    verifier = ethers.Wallet.createRandom().connect(ethers.provider)
    verifierDestination = await ethers.Wallet.createRandom().getAddress()

    // Create provision
    await stake({ horizonStaking, graphToken, serviceProvider, tokens: provisionTokens })
    await createProvision({
      horizonStaking,
      serviceProvider,
      verifier: verifier.address,
      tokens: provisionTokens,
      maxVerifierCut,
      thawingPeriod,
    })

    // Send funds to delegator
    await graphToken.connect(serviceProvider).transfer(delegator.address, delegationTokens * 3n)

    // Initialize delegation pool if it does not exist
    await delegate({
      horizonStaking,
      graphToken,
      delegator,
      serviceProvider,
      verifier: verifier.address,
      tokens: delegationTokens,
      minSharesOut: 0n,
    })

    // Send eth to verifier to cover gas fees
    await serviceProvider.sendTransaction({
      to: verifier.address,
      value: ethers.parseEther('0.1'),
    })
  })

  it('should slash service provider tokens', async () => {
    const slashTokens = ethers.parseEther('1000')
    const tokensVerifier = slashTokens / 2n
    const provisionBefore = await horizonStaking.getProvision(serviceProvider.address, verifier.address)
    const verifierDestinationBalanceBefore = await graphToken.balanceOf(verifierDestination)

    // Slash provision
    await slash({
      horizonStaking,
      verifier,
      serviceProvider: serviceProvider.address,
      tokens: slashTokens,
      tokensVerifier,
      verifierDestination,
    })

    // Verify provision tokens are reduced
    const provisionAfter = await horizonStaking.getProvision(serviceProvider.address, verifier.address)
    expect(provisionAfter.tokens).to.equal(provisionBefore.tokens - slashTokens, 'Provision tokens should be reduced')

    // Verify verifier destination received the tokens
    const verifierDestinationBalanceAfter = await graphToken.balanceOf(verifierDestination)
    expect(verifierDestinationBalanceAfter).to.equal(verifierDestinationBalanceBefore + tokensVerifier, 'Verifier destination should receive the tokens')
  })

  it('should slash service provider tokens when tokens are thawing', async () => {
    // Start thawing
    const thawTokens = ethers.parseEther('1000')
    await thaw({
      horizonStaking,
      serviceProvider,
      verifier: verifier.address,
      tokens: thawTokens,
    })

    const slashTokens = ethers.parseEther('500')
    const tokensVerifier = slashTokens / 2n
    const provisionBefore = await horizonStaking.getProvision(serviceProvider.address, verifier.address)
    const verifierDestinationBalanceBefore = await graphToken.balanceOf(verifierDestination)

    // Slash provision
    await slash({
      horizonStaking,
      verifier,
      serviceProvider: serviceProvider.address,
      tokens: slashTokens,
      tokensVerifier,
      verifierDestination,
    })

    // Verify provision tokens are reduced
    const provisionAfter = await horizonStaking.getProvision(serviceProvider.address, verifier.address)
    expect(provisionAfter.tokens).to.equal(provisionBefore.tokens - slashTokens, 'Provision tokens should be reduced')

    // Verify verifier destination received the tokens
    const verifierDestinationBalanceAfter = await graphToken.balanceOf(verifierDestination)
    expect(verifierDestinationBalanceAfter).to.equal(verifierDestinationBalanceBefore + tokensVerifier, 'Verifier destination should receive the tokens')
  })

  it('should only slash service provider when delegation slashing is disabled', async () => {
    const slashingVerifier = ethers.Wallet.createRandom().connect(ethers.provider)
    const slashTokens = provisionTokens + delegationTokens
    const tokensVerifier = slashTokens / 2n

    // Send eth to slashing verifier to cover gas fees
    await serviceProvider.sendTransaction({
      to: slashingVerifier.address,
      value: ethers.parseEther('0.5'),
    })

    // Create provision for slashing verifier
    await stake({ horizonStaking, graphToken, serviceProvider, tokens: provisionTokens })
    await createProvision({
      horizonStaking,
      serviceProvider,
      verifier: slashingVerifier.address,
      tokens: provisionTokens,
      maxVerifierCut,
      thawingPeriod,
    })

    // Initialize delegation pool for slashing verifier
    await delegate({
      horizonStaking,
      graphToken,
      delegator,
      serviceProvider,
      verifier: slashingVerifier.address,
      tokens: delegationTokens,
      minSharesOut: 0n,
    })

    // Get delegation pool state before slashing
    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, slashingVerifier.address)

    // Slash the provision for all service provider and delegation pool tokens
    await slash({
      horizonStaking,
      verifier: slashingVerifier,
      serviceProvider: serviceProvider.address,
      tokens: slashTokens,
      tokensVerifier,
      verifierDestination,
    })

    // Verify provision tokens were completely slashed
    const provisionAfter = await horizonStaking.getProvision(serviceProvider.address, slashingVerifier.address)
    expect(provisionAfter.tokens).to.be.equal(0, 'Provision tokens should be slashed completely')

    // Verify delegation pool tokens are not reduced
    const poolAfter = await horizonStaking.getDelegationPool(serviceProvider.address, slashingVerifier.address)
    expect(poolAfter.tokens).to.equal(poolBefore.tokens, 'Delegation pool tokens should not be reduced')
    expect(poolAfter.shares).to.equal(poolBefore.shares, 'Delegation pool shares should remain the same')
  })
})

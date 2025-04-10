import hre from 'hardhat'

import { ethers } from 'hardhat'
import { expect } from 'chai'
import { ONE_MILLION } from '@graphprotocol/toolshed'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'

import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Slasher', () => {
  let snapshotId: string
  let serviceProvider: HardhatEthersSigner
  let delegator: HardhatEthersSigner
  let verifier: HardhatEthersSigner
  let slashingVerifier: HardhatEthersSigner
  let verifierDestination: string

  const maxVerifierCut = 1000000n // 100%
  const thawingPeriod = 2419200n // 28 days
  const provisionTokens = ethers.parseEther('10000')
  const delegationTokens = ethers.parseEther('1000')

  const graph = hre.graph()
  const { provision, delegate } = graph.horizon.actions
  const horizonStaking = graph.horizon.contracts.HorizonStaking
  const graphToken = graph.horizon.contracts.L2GraphToken

  before(async () => {
    // index 2 is registered as slasher so we skip it
    [serviceProvider, delegator, , verifier, slashingVerifier] = await ethers.getSigners()
    verifierDestination = ethers.Wallet.createRandom().address
    await setGRTBalance(graph.provider, graphToken.target, serviceProvider.address, ONE_MILLION)
    await setGRTBalance(graph.provider, graphToken.target, delegator.address, ONE_MILLION)
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])

    // Create provision
    await provision(serviceProvider, [serviceProvider.address, verifier.address, provisionTokens, maxVerifierCut, thawingPeriod])

    // Send funds to delegator
    await graphToken.connect(serviceProvider).transfer(delegator.address, delegationTokens * 3n)

    // Initialize delegation pool if it does not exist
    await delegate(delegator, [serviceProvider.address, verifier.address, delegationTokens, 0n])

    // Send eth to verifier to cover gas fees
    await serviceProvider.sendTransaction({
      to: verifier,
      value: ethers.parseEther('0.1'),
    })
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  it('should slash service provider tokens', async () => {
    const slashTokens = ethers.parseEther('1000')
    const tokensVerifier = slashTokens / 2n
    const provisionBefore = await horizonStaking.getProvision(serviceProvider.address, verifier)
    const verifierDestinationBalanceBefore = await graphToken.balanceOf(verifierDestination)

    // Slash provision
    await horizonStaking.connect(verifier).slash(serviceProvider.address, slashTokens, tokensVerifier, verifierDestination)

    // Verify provision tokens are reduced
    const provisionAfter = await horizonStaking.getProvision(serviceProvider.address, verifier)
    expect(provisionAfter.tokens).to.equal(provisionBefore.tokens - slashTokens, 'Provision tokens should be reduced')

    // Verify verifier destination received the tokens
    const verifierDestinationBalanceAfter = await graphToken.balanceOf(verifierDestination)
    expect(verifierDestinationBalanceAfter).to.equal(verifierDestinationBalanceBefore + tokensVerifier, 'Verifier destination should receive the tokens')
  })

  it('should slash service provider tokens when tokens are thawing', async () => {
    // Start thawing
    const thawTokens = ethers.parseEther('1000')
    await horizonStaking.connect(serviceProvider).thaw(serviceProvider.address, verifier.address, thawTokens)

    const slashTokens = ethers.parseEther('500')
    const tokensVerifier = slashTokens / 2n
    const provisionBefore = await horizonStaking.getProvision(serviceProvider.address, verifier)
    const verifierDestinationBalanceBefore = await graphToken.balanceOf(verifierDestination)

    // Slash provision
    await horizonStaking.connect(verifier).slash(serviceProvider.address, slashTokens, tokensVerifier, verifierDestination)

    // Verify provision tokens are reduced
    const provisionAfter = await horizonStaking.getProvision(serviceProvider.address, verifier)
    expect(provisionAfter.tokens).to.equal(provisionBefore.tokens - slashTokens, 'Provision tokens should be reduced')

    // Verify verifier destination received the tokens
    const verifierDestinationBalanceAfter = await graphToken.balanceOf(verifierDestination)
    expect(verifierDestinationBalanceAfter).to.equal(verifierDestinationBalanceBefore + tokensVerifier, 'Verifier destination should receive the tokens')
  })

  it('should only slash service provider when delegation slashing is disabled', async () => {
    const slashTokens = provisionTokens + delegationTokens
    const tokensVerifier = slashTokens / 2n

    // Send eth to slashing verifier to cover gas fees
    await serviceProvider.sendTransaction({
      to: slashingVerifier.address,
      value: ethers.parseEther('0.5'),
    })

    // Create provision for slashing verifier
    await provision(serviceProvider, [serviceProvider.address, slashingVerifier.address, provisionTokens, maxVerifierCut, thawingPeriod])

    // Initialize delegation pool for slashing verifier
    await delegate(serviceProvider, [serviceProvider.address, slashingVerifier.address, delegationTokens, 0n])

    // Get delegation pool state before slashing
    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, slashingVerifier.address)

    // Slash the provision for all service provider and delegation pool tokens
    await horizonStaking.connect(slashingVerifier).slash(serviceProvider.address, slashTokens, tokensVerifier, verifierDestination)

    // Verify provision tokens were completely slashed
    const provisionAfter = await horizonStaking.getProvision(serviceProvider.address, slashingVerifier.address)
    expect(provisionAfter.tokens).to.be.equal(0, 'Provision tokens should be slashed completely')

    // Verify delegation pool tokens are not reduced
    const poolAfter = await horizonStaking.getDelegationPool(serviceProvider.address, slashingVerifier.address)
    expect(poolAfter.tokens).to.equal(poolBefore.tokens, 'Delegation pool tokens should not be reduced')
    expect(poolAfter.shares).to.equal(poolBefore.shares, 'Delegation pool shares should remain the same')
  })
})

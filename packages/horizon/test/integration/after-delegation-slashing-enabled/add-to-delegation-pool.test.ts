import hre from 'hardhat'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { IHorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import {
  addToDelegationPool,
  createProvision,
  delegate,
  slash,
  stake,
} from '../shared/staking'

describe('Add to delegation pool', () => {
  let horizonStaking: IHorizonStaking
  let graphToken: IGraphToken
  let serviceProvider: SignerWithAddress
  let delegator: SignerWithAddress
  let signer: SignerWithAddress
  let verifier: string

  const maxVerifierCut = 1000000
  const thawingPeriod = 2419200 // 28 days
  const tokens = ethers.parseEther('100000')
  const delegationTokens = ethers.parseEther('1000')

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking as unknown as IHorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken

    [serviceProvider, delegator, signer] = await ethers.getSigners()
    verifier = await ethers.Wallet.createRandom().getAddress()

    // Service provider stake
    await stake({
      horizonStaking,
      graphToken,
      serviceProvider,
      tokens,
    })

    // Create provision
    const provisionTokens = ethers.parseEther('1000')
    await createProvision({
      horizonStaking,
      serviceProvider,
      verifier,
      tokens: provisionTokens,
      maxVerifierCut,
      thawingPeriod,
    })

    // Send funds to delegator and signer
    await graphToken.connect(serviceProvider).transfer(delegator.address, tokens)
    await graphToken.connect(serviceProvider).transfer(signer.address, tokens)

    // Initialize delegation pool
    await delegate({
      horizonStaking,
      graphToken,
      delegator,
      serviceProvider,
      verifier,
      tokens: delegationTokens,
      minSharesOut: 0n,
    })
  })

  it('should recover delegation pool from invalid state by adding tokens', async () => {
    // Setup a new verifier
    const newVerifier = ethers.Wallet.createRandom().connect(ethers.provider)
    // Send eth to new verifier to cover gas fees
    await serviceProvider.sendTransaction({
      to: newVerifier.address,
      value: ethers.parseEther('0.1'),
    })

    // Create a provision for the new verifier
    const newVerifierProvisionTokens = ethers.parseEther('1000')
    await createProvision({
      horizonStaking,
      serviceProvider,
      verifier: newVerifier.address,
      tokens: newVerifierProvisionTokens,
      maxVerifierCut,
      thawingPeriod,
    })

    // Initialize delegation pool
    const initialDelegation = ethers.parseEther('1000')
    await delegate({
      horizonStaking,
      graphToken,
      delegator,
      serviceProvider,
      verifier: newVerifier.address,
      tokens: initialDelegation,
      minSharesOut: 0n,
    })

    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, newVerifier.address)

    // Slash entire provision (service provider tokens + delegation pool tokens)
    const slashTokens = newVerifierProvisionTokens + initialDelegation
    const tokensVerifier = newVerifierProvisionTokens / 2n
    await slash({
      horizonStaking,
      verifier: newVerifier,
      serviceProvider,
      tokens: slashTokens,
      tokensVerifier,
      verifierDestination: newVerifier.address,
    })

    // Delegating should revert since pool.tokens == 0 and pool.shares != 0
    const delegateTokens = ethers.parseEther('500')
    await expect(
      delegate({
        horizonStaking,
        graphToken,
        delegator,
        serviceProvider,
        verifier: newVerifier.address,
        tokens: delegateTokens,
        minSharesOut: 0n,
      }),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPoolState')

    // Add tokens to the delegation pool to recover the pool
    const recoverPoolTokens = ethers.parseEther('500')
    await addToDelegationPool({
      horizonStaking,
      graphToken,
      signer,
      serviceProvider,
      verifier: newVerifier.address,
      tokens: recoverPoolTokens,
    })

    // Verify delegation pool is recovered
    const poolAfter = await horizonStaking.getDelegationPool(serviceProvider.address, newVerifier.address)
    expect(poolAfter.tokens).to.equal(recoverPoolTokens, 'Pool tokens should be recovered')
    expect(poolAfter.shares).to.equal(poolBefore.shares, 'Pool shares should remain the same')

    // Delegation should now succeed
    await delegate({
      horizonStaking,
      graphToken,
      delegator,
      serviceProvider,
      verifier: newVerifier.address,
      tokens: delegateTokens,
      minSharesOut: 0n,
    })
  })
})

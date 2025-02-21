import hre from 'hardhat'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import {
  addToDelegationPool,
  createProvision,
  delegate,
  slash,
  stake,
} from '../shared/staking'

describe('Add to delegation pool (after transition period)', () => {
  let horizonStaking: HorizonStaking
  let graphToken: IGraphToken
  let governor: SignerWithAddress
  let serviceProvider: SignerWithAddress
  let delegator: SignerWithAddress
  let signer: SignerWithAddress
  let verifier: string
  let slashingVerifier: SignerWithAddress

  const maxVerifierCut = 1000000
  const thawingPeriod = 2419200 // 28 days
  const tokens = ethers.parseEther('100000')
  const delegationTokens = ethers.parseEther('1000')

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken

    [serviceProvider, governor, delegator, signer, slashingVerifier] = await ethers.getSigners()
    verifier = await ethers.Wallet.createRandom().getAddress()

    // Enable delegation slashing
    await horizonStaking.connect(governor).setDelegationSlashingEnabled()

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

  it('should add tokens to an existing delegation pool', async () => {
    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, verifier)
    const addTokens = ethers.parseEther('500')

    // Add tokens to the delegation pool
    await addToDelegationPool({
      horizonStaking,
      graphToken,
      signer,
      serviceProvider,
      verifier,
      tokens: addTokens,
    })

    // Verify tokens were added to the pool
    const poolAfter = await horizonStaking.getDelegationPool(serviceProvider.address, verifier)
    expect(poolAfter.tokens).to.equal(poolBefore.tokens + addTokens, 'Pool tokens should increase')
    expect(poolAfter.shares).to.equal(poolBefore.shares, 'Pool shares should remain the same')
  })

  it('should revert when adding tokens to a non-existent provision', async () => {
    const invalidVerifier = await ethers.Wallet.createRandom().getAddress()
    const addTokens = ethers.parseEther('500')

    // Attempt to add tokens to a non-existent provision
    await expect(
      addToDelegationPool({
        horizonStaking,
        graphToken,
        signer,
        serviceProvider,
        verifier: invalidVerifier,
        tokens: addTokens,
      }),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidProvision')
  })

  it('should revert when adding tokens to a provision with zero shares in delegation pool', async () => {
    // Create new provision without any delegations
    const newVerifier = await ethers.Wallet.createRandom().getAddress()
    const newVerifierProvisionTokens = ethers.parseEther('1000')
    await createProvision({
      horizonStaking,
      serviceProvider,
      verifier: newVerifier,
      tokens: newVerifierProvisionTokens,
      maxVerifierCut,
      thawingPeriod,
    })

    // Attempt to add tokens to the new provision
    const addTokens = ethers.parseEther('500')
    await expect(
      addToDelegationPool({
        horizonStaking,
        graphToken,
        signer,
        serviceProvider,
        verifier: newVerifier,
        tokens: addTokens,
      }),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPool')
  })

  it('should recover delegation pool from invalid state by adding tokens', async () => {
    // Create a new provision for the slashing verifier
    const slashingVerifierProvisionTokens = ethers.parseEther('1000')
    await createProvision({
      horizonStaking,
      serviceProvider,
      verifier: slashingVerifier.address,
      tokens: slashingVerifierProvisionTokens,
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
      verifier: slashingVerifier.address,
      tokens: initialDelegation,
      minSharesOut: 0n,
    })
    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, slashingVerifier.address)

    // Slash entire provision (service provider tokens + delegation pool tokens)
    const slashTokens = slashingVerifierProvisionTokens + initialDelegation
    const tokensVerifier = slashingVerifierProvisionTokens / 2n
    await slash({
      horizonStaking,
      verifier: slashingVerifier,
      serviceProvider,
      tokens: slashTokens,
      tokensVerifier,
      verifierDestination: slashingVerifier.address,
    })

    // Log pool tokens after slashing
    // const poolAfterSlashing = await horizonStaking.getDelegationPool(serviceProvider.address, slashingVerifier.address)
    // console.log('Pool tokens after slashing:', poolAfterSlashing.tokens.toString())

    // Delegating should revert since pool.tokens == 0 and pool.shares != 0
    const delegateTokens = ethers.parseEther('500')
    await expect(
      delegate({
        horizonStaking,
        graphToken,
        delegator,
        serviceProvider,
        verifier: slashingVerifier.address,
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
      verifier: slashingVerifier.address,
      tokens: recoverPoolTokens,
    })

    // Verify delegation pool is recovered
    const poolAfter = await horizonStaking.getDelegationPool(serviceProvider.address, slashingVerifier.address)
    expect(poolAfter.tokens).to.equal(recoverPoolTokens, 'Pool tokens should be recovered')
    expect(poolAfter.shares).to.equal(poolBefore.shares, 'Pool shares should remain the same')

    // Delegation should now succeed
    await delegate({
      horizonStaking,
      graphToken,
      delegator,
      serviceProvider,
      verifier: slashingVerifier.address,
      tokens: delegateTokens,
      minSharesOut: 0n,
    })
  })
})

import hre from 'hardhat'

import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { HorizonStakingActions } from '@graphprotocol/toolshed/actions/horizon'

import type { HorizonStaking, L2GraphToken } from '@graphprotocol/toolshed/deployments/horizon'
import type { GraphRuntimeEnvironment } from 'hardhat-graph-protocol'

describe('Add to delegation pool', () => {
  let graph: GraphRuntimeEnvironment
  let horizonStaking: HorizonStaking
  let graphToken: L2GraphToken
  let serviceProvider: HardhatEthersSigner
  let delegator: HardhatEthersSigner
  let signer: HardhatEthersSigner
  let verifier: string

  const maxVerifierCut = 1000000n
  const thawingPeriod = 2419200n // 28 days
  const tokens = ethers.parseEther('100000')
  const delegationTokens = ethers.parseEther('1000')

  before(async () => {
    graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken

    ;[serviceProvider, delegator, signer] = await ethers.getSigners()
    verifier = ethers.Wallet.createRandom().address

    // Service provider stake
    await HorizonStakingActions.stake({
      horizonStaking,
      graphToken,
      serviceProvider,
      tokens,
    })

    // Create provision
    const provisionTokens = ethers.parseEther('1000')
    await HorizonStakingActions.createProvision({
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
    await HorizonStakingActions.delegate({
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
    await HorizonStakingActions.addToDelegationPool({
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
      HorizonStakingActions.addToDelegationPool({
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
    await HorizonStakingActions.createProvision({
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
      HorizonStakingActions.addToDelegationPool({
        horizonStaking,
        graphToken,
        signer,
        serviceProvider,
        verifier: newVerifier,
        tokens: addTokens,
      }),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPool')
  })
})

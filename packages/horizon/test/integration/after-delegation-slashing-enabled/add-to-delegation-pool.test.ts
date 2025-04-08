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
  let verifier: HardhatEthersSigner
  let newVerifier: HardhatEthersSigner
  let snapshotId: string

  const maxVerifierCut = 1000000n
  const thawingPeriod = 2419200n // 28 days
  const tokens = ethers.parseEther('100000')
  const delegationTokens = ethers.parseEther('1000')

  before(async () => {
    graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken

    const signers = await ethers.getSigners()
    serviceProvider = signers[8]
    delegator = signers[13]
    signer = signers[19]
    verifier = signers[15]
    newVerifier = signers[16]
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])

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
      verifier: verifier.address,
      tokens: provisionTokens,
      maxVerifierCut,
      thawingPeriod,
    })

    // Initialize delegation pool
    await HorizonStakingActions.delegate({
      horizonStaking,
      graphToken,
      delegator,
      serviceProvider,
      verifier: verifier.address,
      tokens: delegationTokens,
      minSharesOut: 0n,
    })
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  it('should recover delegation pool from invalid state by adding tokens', async () => {
    // Send eth to new verifier to cover gas fees
    await serviceProvider.sendTransaction({
      to: newVerifier.address,
      value: ethers.parseEther('0.1'),
    })

    // Create a provision for the new verifier
    const newVerifierProvisionTokens = ethers.parseEther('1000')
    await HorizonStakingActions.createProvision({
      horizonStaking,
      serviceProvider,
      verifier: newVerifier.address,
      tokens: newVerifierProvisionTokens,
      maxVerifierCut,
      thawingPeriod,
    })

    // Initialize delegation pool
    const initialDelegation = ethers.parseEther('1000')
    await HorizonStakingActions.delegate({
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
    await HorizonStakingActions.slash({
      horizonStaking,
      verifier: newVerifier,
      serviceProvider: serviceProvider.address,
      tokens: slashTokens,
      tokensVerifier,
      verifierDestination: newVerifier.address,
    })

    // Delegating should revert since pool.tokens == 0 and pool.shares != 0
    const delegateTokens = ethers.parseEther('500')
    await expect(
      HorizonStakingActions.delegate({
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
    await HorizonStakingActions.addToDelegationPool({
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
    await HorizonStakingActions.delegate({
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

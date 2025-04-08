import hre from 'hardhat'

import { ethers } from 'hardhat'
import { expect } from 'chai'

import type { HorizonStaking, L2GraphToken } from '@graphprotocol/toolshed/deployments/horizon'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Add to delegation pool', () => {
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
    const graph = hre.graph()

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
    await graphToken.connect(serviceProvider).approve(horizonStaking.target, tokens)
    await horizonStaking.connect(serviceProvider).stake(tokens)

    // Create provision
    const provisionTokens = ethers.parseEther('1000')
    await horizonStaking.connect(serviceProvider).provision(serviceProvider.address, verifier.address, provisionTokens, maxVerifierCut, thawingPeriod)

    // Initialize delegation pool
    await graphToken.connect(delegator).approve(horizonStaking.target, delegationTokens)
    await horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, verifier.address, delegationTokens, 0n)
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
    await horizonStaking.connect(serviceProvider).provision(serviceProvider.address, newVerifier.address, newVerifierProvisionTokens, maxVerifierCut, thawingPeriod)

    // Initialize delegation pool
    const initialDelegation = ethers.parseEther('1000')
    await graphToken.connect(delegator).approve(horizonStaking.target, initialDelegation)
    await horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, newVerifier.address, initialDelegation, 0n)

    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, newVerifier.address)

    // Slash entire provision (service provider tokens + delegation pool tokens)
    const slashTokens = newVerifierProvisionTokens + initialDelegation
    const tokensVerifier = newVerifierProvisionTokens / 2n
    await horizonStaking.connect(newVerifier).slash(serviceProvider.address, slashTokens, tokensVerifier, newVerifier.address)

    // Delegating should revert since pool.tokens == 0 and pool.shares != 0
    const delegateTokens = ethers.parseEther('500')
    await graphToken.connect(delegator).approve(horizonStaking.target, delegateTokens)
    await expect(
      horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, newVerifier.address, delegateTokens, 0n),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPoolState')

    // Add tokens to the delegation pool to recover the pool
    const recoverPoolTokens = ethers.parseEther('500')
    await graphToken.connect(signer).approve(horizonStaking.target, recoverPoolTokens)
    await horizonStaking.connect(signer).addToDelegationPool(serviceProvider.address, newVerifier.address, recoverPoolTokens)

    // Verify delegation pool is recovered
    const poolAfter = await horizonStaking.getDelegationPool(serviceProvider.address, newVerifier.address)
    expect(poolAfter.tokens).to.equal(recoverPoolTokens, 'Pool tokens should be recovered')
    expect(poolAfter.shares).to.equal(poolBefore.shares, 'Pool shares should remain the same')

    // Delegation should now succeed
    await graphToken.connect(delegator).approve(horizonStaking.target, delegateTokens)
    await horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, newVerifier.address, delegateTokens, 0n)
  })
})

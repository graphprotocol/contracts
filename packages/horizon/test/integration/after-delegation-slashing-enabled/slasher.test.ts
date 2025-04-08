import hre from 'hardhat'

import { ethers } from 'hardhat'
import { expect } from 'chai'

import type { HorizonStaking, L2GraphToken } from '@graphprotocol/toolshed/deployments/horizon'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Slasher', () => {
  let snapshotId: string
  let horizonStaking: HorizonStaking
  let graphToken: L2GraphToken
  let serviceProvider: HardhatEthersSigner
  let delegator: HardhatEthersSigner
  let verifier: HardhatEthersSigner
  let verifierDestination: string

  const maxVerifierCut = 1000000n // 100%
  const thawingPeriod = 2419200n // 28 days
  const provisionTokens = ethers.parseEther('10000')
  const delegationTokens = ethers.parseEther('1000')

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken

    // index 2 is registered as slasher so we skip it
    ;[serviceProvider, delegator, , verifier] = await ethers.getSigners()
    verifierDestination = ethers.Wallet.createRandom().address
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
    // Check that delegation slashing is enabled
    const delegationSlashingEnabled = await horizonStaking.isDelegationSlashingEnabled()
    expect(delegationSlashingEnabled).to.be.equal(true, 'Delegation slashing should be enabled')

    // Send funds to delegator
    await graphToken.connect(serviceProvider).transfer(delegator.address, delegationTokens * 3n)
    // Create provision
    await graphToken.connect(serviceProvider).approve(horizonStaking.target, provisionTokens)
    await horizonStaking.connect(serviceProvider).stake(provisionTokens)
    await horizonStaking.connect(serviceProvider).provision(serviceProvider.address, verifier.address, provisionTokens, maxVerifierCut, thawingPeriod)

    // Initialize delegation pool if it does not exist
    await graphToken.connect(delegator).approve(horizonStaking.target, delegationTokens)
    await horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, verifier.address, delegationTokens, 0n)

    // Send eth to verifier to cover gas fees
    await serviceProvider.sendTransaction({
      to: verifier.address,
      value: ethers.parseEther('0.1'),
    })
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  it('should slash service provider and delegation pool tokens', async () => {
    const provisionBefore = await horizonStaking.getProvision(serviceProvider.address, verifier.address)
    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, verifier.address)
    const slashTokens = provisionBefore.tokens + poolBefore.tokens / 2n
    const tokensVerifier = slashTokens / 2n

    // Slash the provision for all service provider and half of the delegation pool tokens
    await horizonStaking.connect(verifier).slash(serviceProvider.address, slashTokens, tokensVerifier, verifierDestination)

    // Verify provision tokens should be slashed completely
    const provisionAfter = await horizonStaking.getProvision(serviceProvider.address, verifier.address)
    expect(provisionAfter.tokens).to.be.equal(0, 'Provision tokens should be slashed completely')

    // Verify the remaining half of the delegation pool tokens are not slashed
    const poolAfter = await horizonStaking.getDelegationPool(serviceProvider.address, verifier.address)
    expect(poolAfter.tokens).to.be.equal(poolBefore.tokens / 2n, 'Delegation pool tokens should be slashed')
    expect(poolAfter.shares).to.equal(poolBefore.shares, 'Delegation pool shares should remain the same')
  })

  it('should handle delegation operations after complete provision is completely slashed', async () => {
    const provisionBefore = await horizonStaking.getProvision(serviceProvider.address, verifier.address)
    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, verifier.address)
    const slashTokens = provisionBefore.tokens + poolBefore.tokens
    const tokensVerifier = slashTokens / 2n

    // Slash the provision for all service provider and delegation pool tokens
    await horizonStaking.connect(verifier).slash(serviceProvider.address, slashTokens, tokensVerifier, verifierDestination)

    const delegateAmount = ethers.parseEther('100')
    const undelegateShares = ethers.parseEther('50')

    // Try to delegate to slashed pool
    await graphToken.connect(delegator).approve(horizonStaking.target, delegateAmount)
    await expect(
      horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](serviceProvider.address, verifier.address, delegateAmount, 0n),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPoolState')

    // Try to undelegate from slashed pool
    await expect(
      horizonStaking.connect(delegator)['undelegate(address,address,uint256)'](serviceProvider.address, verifier.address, undelegateShares),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPoolState')

    // Try to withdraw from slashed pool
    await expect(
      horizonStaking.connect(delegator)['withdrawDelegated(address,address,uint256)'](serviceProvider.address, verifier.address, 1n),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPoolState')
  })
})

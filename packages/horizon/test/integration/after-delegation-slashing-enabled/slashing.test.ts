import hre from 'hardhat'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HDNodeWallet } from 'ethers'
import { HorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import {
  createProvision,
  delegate,
  slash,
  stake,
  undelegate,
  withdrawDelegated,
} from '../shared/staking'

describe('Slashing', () => {
  let horizonStaking: HorizonStaking
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

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken

    [serviceProvider, delegator] = await ethers.getSigners()

    // Send funds to delegator
    await graphToken.connect(serviceProvider).transfer(delegator.address, delegationTokens * 3n)
  })

  beforeEach(async () => {
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

  it('should slash service provider and delegation pool tokens', async () => {
    const provisionBefore = await horizonStaking.getProvision(serviceProvider.address, verifier.address)
    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, verifier.address)
    const slashTokens = provisionBefore.tokens + poolBefore.tokens / 2n
    const tokensVerifier = slashTokens / 2n

    // Slash the provision for all service provider and half of the delegation pool tokens
    await slash({
      horizonStaking,
      verifier,
      serviceProvider,
      tokens: slashTokens,
      tokensVerifier,
      verifierDestination,
    })

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
    await slash({
      horizonStaking,
      verifier,
      serviceProvider,
      tokens: slashTokens,
      tokensVerifier,
      verifierDestination,
    })

    const delegateAmount = ethers.parseEther('100')
    const undelegateShares = ethers.parseEther('50')

    // Try to delegate to slashed pool
    await expect(
      delegate({
        horizonStaking,
        graphToken,
        delegator,
        serviceProvider,
        verifier: verifier.address,
        tokens: delegateAmount,
        minSharesOut: 0n,
      }),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPoolState')

    // Try to undelegate from slashed pool
    await expect(
      undelegate({
        horizonStaking,
        delegator,
        serviceProvider,
        verifier: verifier.address,
        shares: undelegateShares,
      }),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPoolState')

    // Try to withdraw from slashed pool
    await expect(
      withdrawDelegated({
        horizonStaking,
        delegator,
        serviceProvider,
        verifier: verifier.address,
        nThawRequests: 1n,
      }),
    ).to.be.revertedWithCustomError(horizonStaking, 'HorizonStakingInvalidDelegationPoolState')
  })
})

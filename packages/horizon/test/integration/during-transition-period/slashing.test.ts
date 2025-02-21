import hre from 'hardhat'
import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import {
  createProvision,
  delegate,
  slash,
  stake,
} from '../shared/staking'

describe('Slashing', () => {
  let horizonStaking: HorizonStaking
  let graphToken: IGraphToken
  let serviceProvider: SignerWithAddress
  let delegator: SignerWithAddress
  let verifier: SignerWithAddress
  let verifierDestination: string

  const maxVerifierCut = 1000000 // 100%
  const thawingPeriod = 2419200 // 28 days
  const provisionTokens = ethers.parseEther('10000')
  const delegationTokens = ethers.parseEther('1000')

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken

    // Verify delegation slashing is disabled
    expect(await horizonStaking.isDelegationSlashingEnabled()).to.be.equal(false, 'Delegation slashing should be disabled')

    ;[serviceProvider, delegator, verifier] = await ethers.getSigners()
    verifierDestination = await ethers.Wallet.createRandom().getAddress()

    // Service provider stake and create provision
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
    await graphToken.connect(serviceProvider).transfer(delegator.address, delegationTokens)

    // Initialize delegation pool
    await delegate({
      horizonStaking,
      graphToken,
      delegator,
      serviceProvider,
      verifier: verifier.address,
      tokens: delegationTokens,
      minSharesOut: 0n,
    })
  })

  it('should only slash service provider when delegation slashing is disabled', async () => {
    const slashTokens = provisionTokens + delegationTokens
    const tokensVerifier = slashTokens / 2n
    const poolBefore = await horizonStaking.getDelegationPool(serviceProvider.address, verifier.address)

    // Slash the provision for all service provider and delegation pool tokens
    await slash({
      horizonStaking,
      verifier,
      serviceProvider,
      tokens: slashTokens,
      tokensVerifier,
      verifierDestination,
    })

    // Verify provision tokens were completely slashed
    const provisionAfter = await horizonStaking.getProvision(serviceProvider.address, verifier.address)
    expect(provisionAfter.tokens).to.be.equal(0, 'Provision tokens should be slashed completely')

    // Verify delegation pool tokens are not reduced
    const poolAfter = await horizonStaking.getDelegationPool(serviceProvider.address, verifier.address)
    expect(poolAfter.tokens).to.equal(poolBefore.tokens, 'Delegation pool tokens should not be reduced')
    expect(poolAfter.shares).to.equal(poolBefore.shares, 'Delegation pool shares should remain the same')
  })
})

import { expect } from 'chai'
import { HorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { ThawRequestType } from '../utils/types'

/* //////////////////////////////////////////////////////////////
                          STAKE MANAGEMENT
////////////////////////////////////////////////////////////// */

export async function stake(
  horizonStaking: HorizonStaking,
  graphToken: IGraphToken,
  serviceProvider: SignerWithAddress,
  tokens: bigint,
): Promise<void> {
  const serviceProviderBalanceBefore = await graphToken.balanceOf(serviceProvider.address)
  const stakingContractBalanceBefore = await graphToken.balanceOf(horizonStaking.target)

  const approveTx = await graphToken.connect(serviceProvider).approve(horizonStaking.target, tokens)
  await approveTx.wait()

  const stakeTx = await horizonStaking.connect(serviceProvider).stake(tokens)
  await stakeTx.wait()

  // Verify tokens were transferred from service provider to horizon staking
  const serviceProviderBalanceAfter = await graphToken.balanceOf(serviceProvider.address)
  expect(serviceProviderBalanceAfter).to.equal(serviceProviderBalanceBefore - tokens, 'Tokens were not transferred from service provider')

  // Verify tokens were transferred to horizon staking
  const stakingContractBalanceAfter = await graphToken.balanceOf(horizonStaking.target)
  expect(stakingContractBalanceAfter).to.equal(stakingContractBalanceBefore + tokens, 'Tokens were not transferred to horizon staking')

  // Verify service provider stake was updated
  const serviceProviderStake = await horizonStaking.getStake(serviceProvider.address)
  expect(serviceProviderStake).to.equal(tokens, 'Service provider stake was not updated')
}

export async function unstake(
  horizonStaking: HorizonStaking,
  graphToken: IGraphToken,
  serviceProvider: SignerWithAddress,
  tokens: bigint,
): Promise<void> {
  const serviceProviderBalanceBefore = await graphToken.balanceOf(serviceProvider.address)
  const stakingContractBalanceBefore = await graphToken.balanceOf(horizonStaking.target)
  const serviceProviderStakeBefore = await horizonStaking.getStake(serviceProvider.address)

  const unstakeTx = await horizonStaking.connect(serviceProvider).unstake(tokens)
  await unstakeTx.wait()

  // Verify tokens were transferred to service provider
  const serviceProviderBalanceAfter = await graphToken.balanceOf(serviceProvider.address)
  expect(serviceProviderBalanceAfter).to.equal(serviceProviderBalanceBefore + tokens, 'Tokens were not transferred to service provider')

  // Verify tokens were transferred from horizon staking contract
  const stakingContractBalanceAfter = await graphToken.balanceOf(horizonStaking.target)
  expect(stakingContractBalanceAfter).to.equal(stakingContractBalanceBefore - tokens, 'Tokens were not transferred from horizon staking contract')

  // Verify service provider stake was updated
  const serviceProviderStakeAfterUnstake = await horizonStaking.getStake(serviceProvider.address)
  expect(serviceProviderStakeAfterUnstake).to.equal(serviceProviderStakeBefore - tokens, 'Service provider stake was not updated')
}

export async function stakeToProvision(
  horizonStaking: HorizonStaking,
  graphToken: IGraphToken,
  serviceProvider: SignerWithAddress,
  verifier: string,
  tokens: bigint,
): Promise<void> {
  // Verify provision exists
  const provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  expect(provision.tokens).to.not.equal(0, 'Provision should exist')

  const serviceProviderBalanceBefore = await graphToken.balanceOf(serviceProvider.address)
  const stakingContractBalanceBefore = await graphToken.balanceOf(horizonStaking.target)

  const approveTx = await graphToken.connect(serviceProvider).approve(horizonStaking.target, tokens)
  await approveTx.wait()

  const stakeToProvisionTx = await horizonStaking.connect(serviceProvider).stakeToProvision(
    serviceProvider.address,
    verifier,
    tokens,
  )
  await stakeToProvisionTx.wait()

  // Verify tokens were transferred from service provider
  const serviceProviderBalanceAfter = await graphToken.balanceOf(serviceProvider.address)
  expect(serviceProviderBalanceAfter).to.equal(serviceProviderBalanceBefore - tokens, 'Tokens were not transferred from service provider')

  // Verify tokens were transferred to horizon staking
  const stakingContractBalanceAfter = await graphToken.balanceOf(horizonStaking.target)
  expect(stakingContractBalanceAfter).to.equal(stakingContractBalanceBefore + tokens, 'Tokens were not transferred to horizon staking')
}

/* ////////////////////////////////////////////////////////////
                        PROVISION MANAGEMENT
////////////////////////////////////////////////////////////// */

export async function provision(
  horizonStaking: HorizonStaking,
  serviceProvider: SignerWithAddress,
  verifier: string,
  tokens: bigint,
  maxVerifierCut: number,
  thawingPeriod: bigint,
): Promise<void> {
  const idleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
  const createProvisionTx = await horizonStaking.connect(serviceProvider).provision(
    serviceProvider.address,
    verifier,
    tokens,
    maxVerifierCut,
    thawingPeriod,
  )
  await createProvisionTx.wait()

  // Verify provision was created
  const provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  expect(provision.tokens).to.equal(tokens, 'Provision tokens were not set')
  expect(provision.maxVerifierCut).to.equal(maxVerifierCut, 'Provision max verifier cut was not set')
  expect(provision.thawingPeriod).to.equal(thawingPeriod, 'Provision thawing period was not set')

  // Verify idle stake was updated
  const idleStakeAfter = await horizonStaking.getIdleStake(serviceProvider.address)
  expect(idleStakeAfter).to.equal(idleStakeBefore - tokens, 'Idle stake was not updated')
}

export async function thaw(
  horizonStaking: HorizonStaking,
  serviceProvider: SignerWithAddress,
  verifier: string,
  tokens: bigint,
): Promise<void> {
  let provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  const provisionTokensBefore = provision.tokens
  const provisionTokensThawingBefore = provision.tokensThawing
  const expectedThawRequestShares = provision.tokensThawing == 0n
    ? tokens
    : ((provision.sharesThawing * tokens + provision.tokensThawing - 1n) / provision.tokensThawing)

  // Thaw tokens from provision
  const thawTx = await horizonStaking.connect(serviceProvider).thaw(
    serviceProvider.address,
    verifier,
    tokens,
  )
  await thawTx.wait()

  // Verify provision tokens were updated
  provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  expect(provision.tokens).to.equal(provisionTokensBefore, 'Provision tokens should not change')
  expect(provision.tokensThawing).to.equal(provisionTokensThawingBefore + tokens, 'Provision tokens were not updated')

  // Verify thaw request was created
  const thawRequestList = await horizonStaking.getThawRequestList(
    ThawRequestType.Provision,
    serviceProvider.address,
    verifier,
    serviceProvider.address,
  )
  // Check the last thaw request we created
  const thawRequestId = thawRequestList.tail
  const thawRequest = await horizonStaking.getThawRequest(
    ThawRequestType.Provision,
    thawRequestId,
  )
  expect(thawRequest.shares).to.equal(expectedThawRequestShares, 'Thaw request shares were not set')
}

export async function addToProvision(
  horizonStaking: HorizonStaking,
  serviceProvider: SignerWithAddress,
  verifier: string,
  tokens: bigint,
): Promise<void> {
  const idleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
  let provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  const provisionTokensBefore = provision.tokens

  const addToProvisionTx = await horizonStaking.connect(serviceProvider).addToProvision(
    serviceProvider.address,
    verifier,
    tokens,
  )
  await addToProvisionTx.wait()

  // Verify tokens were added to provision
  provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  expect(provision.tokens).to.equal(provisionTokensBefore + tokens, 'Tokens were not added to provision')

  // Verify idle stake was updated
  const idleStakeAfter = await horizonStaking.getIdleStake(serviceProvider.address)
  expect(idleStakeAfter).to.equal(idleStakeBefore - tokens, 'Idle stake was not updated')
}

export async function deprovision(
  horizonStaking: HorizonStaking,
  serviceProvider: SignerWithAddress,
  verifier: string,
  nThawRequests: bigint,
): Promise<void> {
  let provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  const provisionTokensBefore = provision.tokens
  const provisionTokensThawingBefore = provision.tokensThawing

  // Find the amount of tokens we are deprovisioning from thaw request shares
  const tokensToDeprovision = await calculateTokensFromThawRequests(
    horizonStaking,
    serviceProvider,
    verifier,
    provision,
    nThawRequests,
  )

  const serviceProviderIdleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
  const deprovisionTx = await horizonStaking.connect(serviceProvider).deprovision(
    serviceProvider.address,
    verifier,
    nThawRequests,
  )
  await deprovisionTx.wait()

  // Verify tokens were added to idle stake
  const serviceProviderIdleStakeAfter = await horizonStaking.getIdleStake(serviceProvider.address)
  expect(serviceProviderIdleStakeAfter).to.equal(serviceProviderIdleStakeBefore + tokensToDeprovision, 'Tokens were not added to idle stake')

  // Verify tokens were removed from provision
  provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  expect(provision.tokens).to.equal(provisionTokensBefore - tokensToDeprovision, 'Provision should be deprovisioned')
  expect(provision.tokensThawing).to.equal(provisionTokensThawingBefore - tokensToDeprovision, 'Provision tokens thawing should be updated')
}

export async function reprovision(
  horizonStaking: HorizonStaking,
  serviceProvider: SignerWithAddress,
  oldVerifier: string,
  newVerifier: string,
  nThawRequests: bigint,
): Promise<void> {
  let oldVerifierProvision = await horizonStaking.getProvision(serviceProvider.address, oldVerifier)
  const oldVerifierProvisionTokens = oldVerifierProvision.tokens
  const oldVerifierProvisionTokensThawing = oldVerifierProvision.tokensThawing
  let newVerifierProvision = await horizonStaking.getProvision(serviceProvider.address, newVerifier)
  const newVerifierProvisionTokens = newVerifierProvision.tokens

  // Find the amount of tokens we are reprovisioning from thaw request shares
  const tokensToReprovision = await calculateTokensFromThawRequests(
    horizonStaking,
    serviceProvider,
    oldVerifier,
    oldVerifierProvision,
    nThawRequests,
  )

  const serviceProviderIdleStakeBefore = await horizonStaking.getIdleStake(serviceProvider.address)
  const reprovisionTx = await horizonStaking.connect(serviceProvider).reprovision(
    serviceProvider.address,
    oldVerifier,
    newVerifier,
    nThawRequests,
  )
  await reprovisionTx.wait()

  // Verify tokens were removed from oldVerifier provision
  oldVerifierProvision = await horizonStaking.getProvision(serviceProvider.address, oldVerifier)
  expect(oldVerifierProvision.tokens).to.equal(oldVerifierProvisionTokens - tokensToReprovision, 'Old provision tokens were not updated')
  expect(oldVerifierProvision.tokensThawing).to.equal(oldVerifierProvisionTokensThawing - tokensToReprovision, 'Old provision tokens thawing were not updated')

  // Verify tokens were added to newVerifier provision
  newVerifierProvision = await horizonStaking.getProvision(serviceProvider.address, newVerifier)
  expect(newVerifierProvision.tokens).to.equal(newVerifierProvisionTokens + tokensToReprovision, 'New provision tokens were not updated')

  // Verify tokens idle did not change
  const serviceProviderIdleStakeAfter = await horizonStaking.getIdleStake(serviceProvider.address)
  expect(serviceProviderIdleStakeAfter).to.equal(serviceProviderIdleStakeBefore, 'Tokens idle should not change')
}

/* ////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
////////////////////////////////////////////////////////////// */

async function calculateTokensFromThawRequests(
  horizonStaking: HorizonStaking,
  serviceProvider: SignerWithAddress,
  verifier: string,
  provision: { tokensThawing: bigint, sharesThawing: bigint },
  nThawRequests: bigint,
): Promise<bigint> {
  const thawRequestList = await horizonStaking.getThawRequestList(
    ThawRequestType.Provision,
    serviceProvider.address,
    verifier,
    serviceProvider.address,
  )

  // If nThawRequests is 0, process all thaw requests
  if (nThawRequests == 0n) {
    nThawRequests = thawRequestList.count
  }

  // Calculate total tokens from thaw request shares
  let totalTokens = 0n
  let thawRequestId = thawRequestList.head
  for (let i = 0; i < nThawRequests; i++) {
    const thawRequest = await horizonStaking.getThawRequest(
      ThawRequestType.Provision,
      thawRequestId,
    )
    totalTokens += (thawRequest.shares * provision.tokensThawing) / provision.sharesThawing
    thawRequestId = thawRequest.next
  }
  return totalTokens
}

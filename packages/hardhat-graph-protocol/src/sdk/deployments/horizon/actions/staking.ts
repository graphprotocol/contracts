import { ethers, HDNodeWallet } from 'ethers'
import { expect } from 'chai'

import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

import { IGraphToken, IHorizonStaking } from '@graphprotocol/horizon'

import { ThawRequestType } from '../utils/types'

/* //////////////////////////////////////////////////////////////
                            EXPORTS
////////////////////////////////////////////////////////////// */

export const HorizonStakingActions = {
  addToDelegationPool,
  delegate,
  deprovision,
  redelegate,
  reprovision,
  stake,
  stakeTo,
  stakeToProvision,
  slash,
  thaw,
  undelegate,
  unstake,
  withdraw,
  withdrawDelegated,
  withdrawDelegatedLegacy,
  createProvision,
  addToProvision
}

/* //////////////////////////////////////////////////////////////
                          STAKE MANAGEMENT
////////////////////////////////////////////////////////////// */

interface StakeParams {
  horizonStaking: IHorizonStaking
  graphToken: IGraphToken
  serviceProvider: HardhatEthersSigner
  tokens: bigint
}

async function stake({
  horizonStaking,
  graphToken,
  serviceProvider,
  tokens,
}: StakeParams): Promise<void> {
  await approve(graphToken, serviceProvider, await horizonStaking.getAddress(), tokens)
  const stakeTx = await horizonStaking.connect(serviceProvider).stake(tokens)
  await stakeTx.wait()
}

interface StakeToParams extends StakeParams {
  signer: HardhatEthersSigner
}

async function stakeTo({
  horizonStaking,
  graphToken,
  signer,
  serviceProvider,
  tokens,
}: StakeToParams): Promise<void> {
  await approve(graphToken, signer, await horizonStaking.getAddress(), tokens)

  const stakeToTx = await horizonStaking.connect(signer).stakeTo(serviceProvider.address, tokens)
  await stakeToTx.wait()
}

interface UnstakeParams extends Omit<StakeParams, 'graphToken'> {}

async function unstake({
  horizonStaking,
  serviceProvider,
  tokens,
}: UnstakeParams): Promise<void> {
  const unstakeTx = await horizonStaking.connect(serviceProvider).unstake(tokens)
  await unstakeTx.wait()
}

interface WithdrawParams extends Omit<StakeParams, 'graphToken' | 'tokens'> {}

async function withdraw({
  horizonStaking,
  serviceProvider,
}: WithdrawParams): Promise<void> {
  const withdrawTx = await horizonStaking.connect(serviceProvider).withdraw()
  await withdrawTx.wait()
}

interface StakeToProvisionParams extends StakeParams {
  verifier: string
}

async function stakeToProvision({
  horizonStaking,
  graphToken,
  serviceProvider,
  verifier,
  tokens,
}: StakeToProvisionParams): Promise<void> {
  // Verify provision exists
  const provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  expect(provision.createdAt).to.not.equal(0n, 'Provision should exist')

  const approveTx = await graphToken.connect(serviceProvider).approve(horizonStaking.target, tokens)
  await approveTx.wait()

  const stakeToProvisionTx = await horizonStaking.connect(serviceProvider).stakeToProvision(
    serviceProvider.address,
    verifier,
    tokens,
  )
  await stakeToProvisionTx.wait()
}

interface SlashParams extends Omit<StakeParams, 'graphToken' | 'serviceProvider'> {
  verifier: HardhatEthersSigner | HDNodeWallet
  serviceProvider: string
  tokens: bigint
  tokensVerifier: bigint
  verifierDestination: string
}

async function slash({
  horizonStaking,
  verifier,
  serviceProvider,
  tokens,
  tokensVerifier,
  verifierDestination,
}: SlashParams): Promise<void> {
  const slashTx = await horizonStaking.connect(verifier).slash(
    serviceProvider,
    tokens,
    tokensVerifier,
    verifierDestination,
  )
  await slashTx.wait()
}

/* ////////////////////////////////////////////////////////////
                        PROVISION MANAGEMENT
////////////////////////////////////////////////////////////// */

interface ProvisionParams {
  horizonStaking: IHorizonStaking
  serviceProvider: HardhatEthersSigner
  verifier: string
  tokens: bigint
  signer?: HardhatEthersSigner
}

interface CreateProvisionParams extends ProvisionParams {
  maxVerifierCut: bigint
  thawingPeriod: bigint
}

async function createProvision({
  horizonStaking,
  serviceProvider,
  verifier,
  tokens,
  maxVerifierCut,
  thawingPeriod,
  signer,
}: CreateProvisionParams): Promise<void> {
  const effectiveSigner = signer || serviceProvider
  const createProvisionTx = await horizonStaking.connect(effectiveSigner).provision(
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
}

async function addToProvision({
  horizonStaking,
  serviceProvider,
  verifier,
  tokens,
  signer,
}: ProvisionParams): Promise<void> {
  const effectiveSigner = signer || serviceProvider
  const addToProvisionTx = await horizonStaking.connect(effectiveSigner).addToProvision(
    serviceProvider.address,
    verifier,
    tokens,
  )
  await addToProvisionTx.wait()
}

async function thaw({
  horizonStaking,
  serviceProvider,
  verifier,
  tokens,
  signer,
}: ProvisionParams): Promise<void> {
  // Get provision state before thawing
  let provision = await horizonStaking.getProvision(serviceProvider.address, verifier)
  const provisionTokensBefore = provision.tokens
  const provisionTokensThawingBefore = provision.tokensThawing
  const expectedThawRequestShares = provision.tokensThawing == 0n
    ? tokens
    : ((provision.sharesThawing * tokens + provision.tokensThawing - 1n) / provision.tokensThawing)

  // Thaw tokens
  const effectiveSigner = signer || serviceProvider
  const thawTx = await horizonStaking.connect(effectiveSigner).thaw(
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

interface DeprovisionParams extends Omit<ProvisionParams, 'tokens'> {
  nThawRequests: bigint
}

async function deprovision({
  horizonStaking,
  serviceProvider,
  verifier,
  nThawRequests,
  signer,
}: DeprovisionParams): Promise<void> {
  const effectiveSigner = signer || serviceProvider
  const deprovisionTx = await horizonStaking.connect(effectiveSigner).deprovision(
    serviceProvider.address,
    verifier,
    nThawRequests,
  )
  await deprovisionTx.wait()
}

interface ReprovisionParams extends Omit<ProvisionParams, 'tokens'> {
  newVerifier: string
  nThawRequests: bigint
}

async function reprovision({
  horizonStaking,
  serviceProvider,
  verifier: oldVerifier,
  newVerifier,
  nThawRequests,
  signer,
}: ReprovisionParams): Promise<void> {
  const effectiveSigner = signer || serviceProvider
  const reprovisionTx = await horizonStaking.connect(effectiveSigner).reprovision(
    serviceProvider.address,
    oldVerifier,
    newVerifier,
    nThawRequests,
  )
  await reprovisionTx.wait()
}

/* ////////////////////////////////////////////////////////////
                            DELEGATION
////////////////////////////////////////////////////////////// */

interface DelegationParams {
  horizonStaking: IHorizonStaking
  delegator: HardhatEthersSigner
  serviceProvider: HardhatEthersSigner
  verifier: string
}

interface DelegateParams extends DelegationParams {
  graphToken: IGraphToken
  tokens: bigint
  minSharesOut: bigint
}

async function delegate({
  horizonStaking,
  graphToken,
  delegator,
  serviceProvider,
  verifier,
  tokens,
  minSharesOut,
}: DelegateParams): Promise<void> {
  // Approve horizon staking contract to pull tokens from delegator
  await approve(graphToken, delegator, await horizonStaking.getAddress(), tokens)

  const delegateTx = await horizonStaking.connect(delegator)['delegate(address,address,uint256,uint256)'](
    serviceProvider.address,
    verifier,
    tokens,
    minSharesOut,
  )
  await delegateTx.wait()
}

interface UndelegateParams extends DelegationParams {
  shares: bigint
}

async function undelegate({
  horizonStaking,
  delegator,
  serviceProvider,
  verifier,
  shares,
}: UndelegateParams): Promise<void> {
  const undelegateTx = await horizonStaking.connect(delegator)['undelegate(address,address,uint256)'](
    serviceProvider.address,
    verifier,
    shares,
  )
  await undelegateTx.wait()
}

interface RedelegateParams extends DelegationParams {
  newServiceProvider: HardhatEthersSigner
  newVerifier: string
  minSharesForNewProvider: bigint
  nThawRequests: bigint
}

async function redelegate({
  horizonStaking,
  delegator,
  serviceProvider,
  verifier,
  newServiceProvider,
  newVerifier,
  minSharesForNewProvider,
  nThawRequests,
}: RedelegateParams): Promise<void> {
  const redelegateTx = await horizonStaking.connect(delegator).redelegate(
    serviceProvider.address,
    verifier,
    newServiceProvider.address,
    newVerifier,
    minSharesForNewProvider,
    nThawRequests,
  )
  await redelegateTx.wait()
}

interface WithdrawDelegatedParams extends DelegationParams {
  nThawRequests: bigint
}

async function withdrawDelegated({
  horizonStaking,
  delegator,
  serviceProvider,
  verifier,
  nThawRequests,
}: WithdrawDelegatedParams): Promise<void> {
  const withdrawDelegatedTx = await horizonStaking.connect(delegator)['withdrawDelegated(address,address,uint256)'](
    serviceProvider.address,
    verifier,
    nThawRequests,
  )
  await withdrawDelegatedTx.wait()
}

interface WithdrawDelegatedLegacyParams extends Omit<DelegationParams, 'verifier'> {}

async function withdrawDelegatedLegacy({
  horizonStaking,
  delegator,
  serviceProvider,
}: WithdrawDelegatedLegacyParams): Promise<void> {
  const withdrawDelegatedTx = await horizonStaking.connect(delegator)['withdrawDelegated(address,address)'](
    serviceProvider.address,
    ethers.ZeroAddress,
  )
  await withdrawDelegatedTx.wait()
}

interface AddToDelegationPoolParams extends Omit<DelegationParams, 'delegator'> {
  graphToken: IGraphToken
  signer: HardhatEthersSigner
  tokens: bigint
}

async function addToDelegationPool({
  horizonStaking,
  graphToken,
  signer,
  serviceProvider,
  verifier,
  tokens,
}: AddToDelegationPoolParams): Promise<void> {
  // Approve horizon staking contract to pull tokens from delegator
  await approve(graphToken, signer, await horizonStaking.getAddress(), tokens)

  // Add tokens to delegation pool
  const addToDelegationPoolTx = await horizonStaking.connect(signer).addToDelegationPool(
    serviceProvider.address,
    verifier,
    tokens,
  )
  await addToDelegationPoolTx.wait()
}

/* ////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
////////////////////////////////////////////////////////////// */

async function approve(
  graphToken: IGraphToken,
  signer: HardhatEthersSigner,
  spender: string,
  tokens: bigint,
): Promise<void> {
  const approveTx = await graphToken.connect(signer).approve(spender, tokens)
  await approveTx.wait()
}

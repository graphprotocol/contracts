import { expect } from 'chai'
import { IHorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { ThawRequestType } from '../utils/types'
import { HDNodeWallet } from 'ethers'

/* //////////////////////////////////////////////////////////////
                          STAKE MANAGEMENT
////////////////////////////////////////////////////////////// */

interface StakeParams {
  horizonStaking: IHorizonStaking
  graphToken: IGraphToken
  serviceProvider: SignerWithAddress
  tokens: bigint
}

export async function stake({
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
  signer: SignerWithAddress
}

export async function stakeTo({
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

export async function unstake({
  horizonStaking,
  serviceProvider,
  tokens,
}: UnstakeParams): Promise<void> {
  const unstakeTx = await horizonStaking.connect(serviceProvider).unstake(tokens)
  await unstakeTx.wait()
}

interface WithdrawParams extends Omit<StakeParams, 'graphToken' | 'tokens'> {}

export async function withdraw({
  horizonStaking,
  serviceProvider,
}: WithdrawParams): Promise<void> {
  const withdrawTx = await horizonStaking.connect(serviceProvider).withdraw()
  await withdrawTx.wait()
}

interface StakeToProvisionParams extends StakeParams {
  verifier: string
}

export async function stakeToProvision({
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

interface SlashParams extends Omit<StakeParams, 'graphToken'> {
  verifier: SignerWithAddress | HDNodeWallet
  tokens: bigint
  tokensVerifier: bigint
  verifierDestination: string
}

export async function slash({
  horizonStaking,
  verifier,
  serviceProvider,
  tokens,
  tokensVerifier,
  verifierDestination,
}: SlashParams): Promise<void> {
  const slashTx = await horizonStaking.connect(verifier).slash(
    serviceProvider.address,
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
  serviceProvider: SignerWithAddress
  verifier: string
  tokens: bigint
  signer?: SignerWithAddress
}

interface CreateProvisionParams extends ProvisionParams {
  maxVerifierCut: number
  thawingPeriod: number
}

interface DeprovisionParams extends Omit<ProvisionParams, 'tokens'> {
  nThawRequests: bigint
}

interface ReprovisionParams extends Omit<ProvisionParams, 'tokens'> {
  newVerifier: string
  nThawRequests: bigint
}

export async function createProvision({
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

export async function addToProvision({
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

export async function thaw({
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

export async function deprovision({
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

export async function reprovision({
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
  delegator: SignerWithAddress
  serviceProvider: SignerWithAddress
  verifier: string
}

interface DelegateParams extends DelegationParams {
  graphToken: IGraphToken
  tokens: bigint
  minSharesOut: bigint
}

export async function delegate({
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

export async function undelegate({
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

interface WithdrawDelegatedParams extends DelegationParams {
  nThawRequests: bigint
}

interface RedelegateParams extends DelegationParams {
  newServiceProvider: SignerWithAddress
  newVerifier: string
  minSharesForNewProvider: bigint
  nThawRequests: bigint
}

export async function redelegate({
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

export async function withdrawDelegated({
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

interface AddToDelegationPoolParams extends Omit<DelegationParams, 'delegator'> {
  graphToken: IGraphToken
  signer: SignerWithAddress
  tokens: bigint
}

export async function addToDelegationPool({
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
  signer: SignerWithAddress,
  spender: string,
  tokens: bigint,
): Promise<void> {
  const approveTx = await graphToken.connect(signer).approve(spender, tokens)
  await approveTx.wait()
}

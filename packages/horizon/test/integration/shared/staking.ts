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
  await approve(graphToken, serviceProvider, await horizonStaking.getAddress(), tokens)
  const stakeTx = await horizonStaking.connect(serviceProvider).stake(tokens)
  await stakeTx.wait()
}

export async function stakeTo(
  horizonStaking: HorizonStaking,
  graphToken: IGraphToken,
  signer: SignerWithAddress,
  serviceProvider: SignerWithAddress,
  tokens: bigint,
): Promise<void> {
  await approve(graphToken, signer, await horizonStaking.getAddress(), tokens)

  const stakeToTx = await horizonStaking.connect(signer).stakeTo(serviceProvider.address, tokens)
  await stakeToTx.wait()
}

export async function unstake(
  horizonStaking: HorizonStaking,
  serviceProvider: SignerWithAddress,
  tokens: bigint,
): Promise<void> {
  const unstakeTx = await horizonStaking.connect(serviceProvider).unstake(tokens)
  await unstakeTx.wait()
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

  const approveTx = await graphToken.connect(serviceProvider).approve(horizonStaking.target, tokens)
  await approveTx.wait()

  const stakeToProvisionTx = await horizonStaking.connect(serviceProvider).stakeToProvision(
    serviceProvider.address,
    verifier,
    tokens,
  )
  await stakeToProvisionTx.wait()
}

/* ////////////////////////////////////////////////////////////
                        PROVISION MANAGEMENT
////////////////////////////////////////////////////////////// */

interface ProvisionParams {
  horizonStaking: HorizonStaking
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
  horizonStaking: HorizonStaking
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

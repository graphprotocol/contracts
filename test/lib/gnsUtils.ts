import { BigNumber } from 'ethers'
import { namehash, solidityKeccak256 } from 'ethers/lib/utils'
import { Curation } from '../../build/types/Curation'
import { L1GNS } from '../../build/types/L1GNS'
import { L2GNS } from '../../build/types/L2GNS'
import { Account, getChainID, randomHexBytes, toBN } from './testHelpers'
import { expect } from 'chai'

// Entities
export interface PublishSubgraph {
  subgraphDeploymentID: string
  versionMetadata: string
  subgraphMetadata: string
}

export interface Subgraph {
  vSignal: BigNumber
  nSignal: BigNumber
  subgraphDeploymentID: string
  reserveRatio: number
  disabled: boolean
  withdrawableGRT: BigNumber
  id?: string
}

export interface AccountDefaultName {
  name: string
  nameIdentifier: string
}

export const DEFAULT_RESERVE_RATIO = 1000000

export const buildSubgraphID = async (
  account: string,
  seqID: BigNumber,
  chainID?: number,
): Promise<string> => {
  chainID = chainID ?? (await getChainID())
  return solidityKeccak256(['address', 'uint256', 'uint256'], [account, seqID, chainID])
}

export const buildLegacySubgraphID = (account: string, seqID: BigNumber): string =>
  solidityKeccak256(['address', 'uint256'], [account, seqID])

export const buildSubgraph = (): PublishSubgraph => {
  return {
    subgraphDeploymentID: randomHexBytes(),
    versionMetadata: randomHexBytes(),
    subgraphMetadata: randomHexBytes(),
  }
}

export const createDefaultName = (name: string): AccountDefaultName => {
  return {
    name: name,
    nameIdentifier: namehash(name),
  }
}

export const getTokensAndVSignal = async (
  subgraphDeploymentID: string,
  curation: Curation,
): Promise<Array<BigNumber>> => {
  const curationPool = await curation.pools(subgraphDeploymentID)
  const vSignal = await curation.getCurationPoolSignal(subgraphDeploymentID)
  return [curationPool.tokens, vSignal]
}

export const publishNewSubgraph = async (
  account: Account,
  newSubgraph: PublishSubgraph,
  gns: L1GNS | L2GNS,
): Promise<Subgraph> => {
  const subgraphID = await buildSubgraphID(
    account.address,
    await gns.nextAccountSeqID(account.address),
  )

  // Send tx
  const tx = gns
    .connect(account.signer)
    .publishNewSubgraph(
      newSubgraph.subgraphDeploymentID,
      newSubgraph.versionMetadata,
      newSubgraph.subgraphMetadata,
    )

  // Check events
  await expect(tx)
    .emit(gns, 'SubgraphPublished')
    .withArgs(subgraphID, newSubgraph.subgraphDeploymentID, DEFAULT_RESERVE_RATIO)
    .emit(gns, 'SubgraphMetadataUpdated')
    .withArgs(subgraphID, newSubgraph.subgraphMetadata)
    .emit(gns, 'SubgraphVersionUpdated')
    .withArgs(subgraphID, newSubgraph.subgraphDeploymentID, newSubgraph.versionMetadata)

  // Check state
  const subgraph = await gns.subgraphs(subgraphID)
  expect(subgraph.vSignal).eq(0)
  expect(subgraph.nSignal).eq(0)
  expect(subgraph.subgraphDeploymentID).eq(newSubgraph.subgraphDeploymentID)
  expect(subgraph.reserveRatio).eq(DEFAULT_RESERVE_RATIO)
  expect(subgraph.disabled).eq(false)
  expect(subgraph.withdrawableGRT).eq(0)

  // Check NFT issuance
  const owner = await gns.ownerOf(subgraphID)
  expect(owner).eq(account.address)

  return { ...subgraph, id: subgraphID }
}

export const publishNewVersion = async (
  account: Account,
  subgraphID: string,
  newSubgraph: PublishSubgraph,
  gns: L1GNS | L2GNS,
  curation: Curation,
) => {
  // Before state
  const ownerTaxPercentage = await gns.ownerTaxPercentage()
  const curationTaxPercentage = await curation.curationTaxPercentage()
  const beforeSubgraph = await gns.subgraphs(subgraphID)

  // Check what selling all nSignal, which == selling all vSignal, should return for tokens
  // NOTE - no tax on burning on nSignal
  const tokensReceivedEstimate = beforeSubgraph.nSignal.gt(0)
    ? (await gns.nSignalToTokens(subgraphID, beforeSubgraph.nSignal))[1]
    : toBN(0)
  // Example:
  // Deposit 100, 5 is taxed, 95 GRT in curve
  // Upgrade - calculate 5% tax on 95 --> 4.75 GRT
  // Multiple by ownerPercentage --> 50% * 4.75 = 2.375 GRT
  // Owner adds 2.375 to 90.25, we deposit 92.625 GRT into the curve
  // Divide this by 0.95 to get exactly 97.5 total tokens to be deposited

  // nSignalToTokens returns the amount of tokens with tax removed
  // already. So we must add in the tokens removed
  const MAX_PPM = 1000000
  const taxOnOriginal = tokensReceivedEstimate.mul(curationTaxPercentage).div(MAX_PPM)
  const totalWithoutOwnerTax = tokensReceivedEstimate.sub(taxOnOriginal)
  const ownerTax = taxOnOriginal.mul(ownerTaxPercentage).div(MAX_PPM)
  const totalWithOwnerTax = totalWithoutOwnerTax.add(ownerTax)
  const totalAdjustedUp = totalWithOwnerTax.mul(MAX_PPM).div(MAX_PPM - curationTaxPercentage)

  // Re-estimate amount of signal to get considering the owner tax paid by the owner

  const { 0: newVSignalEstimate, 1: newCurationTaxEstimate } = beforeSubgraph.nSignal.gt(0)
    ? await curation.tokensToSignal(newSubgraph.subgraphDeploymentID, totalAdjustedUp)
    : [toBN(0), toBN(0)]

  // Send tx
  const tx = gns
    .connect(account.signer)
    .publishNewVersion(subgraphID, newSubgraph.subgraphDeploymentID, newSubgraph.versionMetadata)
  const txResult = expect(tx)
    .emit(gns, 'SubgraphVersionUpdated')
    .withArgs(subgraphID, newSubgraph.subgraphDeploymentID, newSubgraph.versionMetadata)

  // Only emits this event if there was actual signal to upgrade
  if (beforeSubgraph.nSignal.gt(0)) {
    txResult
      .emit(gns, 'SubgraphUpgraded')
      .withArgs(subgraphID, newVSignalEstimate, totalAdjustedUp, newSubgraph.subgraphDeploymentID)
  }
  await txResult

  // Check curation vSignal old are set to zero
  const [afterTokensOldCuration, afterVSignalOldCuration] = await getTokensAndVSignal(
    beforeSubgraph.subgraphDeploymentID,
    curation,
  )
  expect(afterTokensOldCuration).eq(0)
  expect(afterVSignalOldCuration).eq(0)

  // Check the vSignal of the new curation curve, and tokens
  const [afterTokensNewCurve, afterVSignalNewCurve] = await getTokensAndVSignal(
    newSubgraph.subgraphDeploymentID,
    curation,
  )
  expect(afterTokensNewCurve).eq(totalAdjustedUp.sub(newCurationTaxEstimate))
  expect(afterVSignalNewCurve).eq(newVSignalEstimate)

  // Check the nSignal pool
  const afterSubgraph = await gns.subgraphs(subgraphID)
  expect(afterSubgraph.vSignal).eq(afterVSignalNewCurve).eq(newVSignalEstimate)
  expect(afterSubgraph.nSignal).eq(beforeSubgraph.nSignal) // should not change
  expect(afterSubgraph.subgraphDeploymentID).eq(newSubgraph.subgraphDeploymentID)

  // Check NFT should not change owner
  const owner = await gns.ownerOf(subgraphID)
  expect(owner).eq(account.address)

  return tx
}

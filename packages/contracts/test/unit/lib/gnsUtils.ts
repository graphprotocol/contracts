import { BigNumber, ContractTransaction } from 'ethers'
import { namehash } from 'ethers/lib/utils'
import { Curation } from '../../../build/types/Curation'
import { L1GNS } from '../../../build/types/L1GNS'
import { L2GNS } from '../../../build/types/L2GNS'
import { expect } from 'chai'
import { L2Curation } from '../../../build/types/L2Curation'
import { GraphToken } from '../../../build/types/GraphToken'
import { L2GraphToken } from '../../../build/types/L2GraphToken'
import { PublishSubgraph, Subgraph, buildSubgraphId, toBN } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

// Entities
export interface AccountDefaultName {
  name: string
  nameIdentifier: string
}

export const DEFAULT_RESERVE_RATIO = 1000000

export const createDefaultName = (name: string): AccountDefaultName => {
  return {
    name: name,
    nameIdentifier: namehash(name),
  }
}

export const getTokensAndVSignal = async (
  subgraphDeploymentID: string,
  curation: Curation | L2Curation,
): Promise<Array<BigNumber>> => {
  const curationPool = await curation.pools(subgraphDeploymentID)
  const vSignal = await curation.getCurationPoolSignal(subgraphDeploymentID)
  return [curationPool.tokens, vSignal]
}

export const publishNewSubgraph = async (
  account: SignerWithAddress,
  newSubgraph: PublishSubgraph,
  gns: L1GNS | L2GNS,
  chainId: number,
): Promise<Subgraph> => {
  const subgraphID = await buildSubgraphId(
    account.address,
    await gns.nextAccountSeqID(account.address),
    chainId,
  )

  // Send tx
  const tx = gns
    .connect(account)
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
  expect(subgraph.__DEPRECATED_reserveRatio).eq(DEFAULT_RESERVE_RATIO)
  expect(subgraph.disabled).eq(false)
  expect(subgraph.withdrawableGRT).eq(0)

  // Check NFT issuance
  const owner = await gns.ownerOf(subgraphID)
  expect(owner).eq(account.address)

  return { ...subgraph, id: subgraphID }
}

export const publishNewVersion = async (
  account: SignerWithAddress,
  subgraphID: string,
  newSubgraph: PublishSubgraph,
  gns: L1GNS | L2GNS,
  curation: Curation | L2Curation,
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

  // Check the vSignal of the new curation curve, and tokens, before upgrading
  const [beforeTokensNewCurve, beforeVSignalNewCurve] = await getTokensAndVSignal(
    newSubgraph.subgraphDeploymentID,
    curation,
  )
  // Send tx
  const tx = gns
    .connect(account)
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
  expect(afterTokensNewCurve).eq(
    beforeTokensNewCurve.add(totalAdjustedUp).sub(newCurationTaxEstimate),
  )
  expect(afterVSignalNewCurve).eq(beforeVSignalNewCurve.add(newVSignalEstimate))

  // Check the nSignal pool
  const afterSubgraph = await gns.subgraphs(subgraphID)
  expect(afterSubgraph.vSignal)
    .eq(afterVSignalNewCurve.sub(beforeVSignalNewCurve))
    .eq(newVSignalEstimate)
  expect(afterSubgraph.nSignal).eq(beforeSubgraph.nSignal) // should not change
  expect(afterSubgraph.subgraphDeploymentID).eq(newSubgraph.subgraphDeploymentID)

  // Check NFT should not change owner
  const owner = await gns.ownerOf(subgraphID)
  expect(owner).eq(account.address)

  return tx
}

export const mintSignal = async (
  account: SignerWithAddress,
  subgraphID: string,
  tokensIn: BigNumber,
  gns: L1GNS | L2GNS,
  curation: Curation | L2Curation,
): Promise<ContractTransaction> => {
  // Before state
  const beforeSubgraph = await gns.subgraphs(subgraphID)
  const [beforeTokens, beforeVSignal] = await getTokensAndVSignal(
    beforeSubgraph.subgraphDeploymentID,
    curation,
  )

  // Deposit
  const {
    0: vSignalExpected,
    1: nSignalExpected,
    2: curationTax,
  } = await gns.tokensToNSignal(subgraphID, tokensIn)
  const tx = gns.connect(account).mintSignal(subgraphID, tokensIn, 0)
  await expect(tx)
    .emit(gns, 'SignalMinted')
    .withArgs(subgraphID, account.address, nSignalExpected, vSignalExpected, tokensIn)

  // After state
  const afterSubgraph = await gns.subgraphs(subgraphID)
  const [afterTokens, afterVSignal] = await getTokensAndVSignal(
    afterSubgraph.subgraphDeploymentID,
    curation,
  )

  // Check state
  expect(afterTokens).eq(beforeTokens.add(tokensIn.sub(curationTax)))
  expect(afterVSignal).eq(beforeVSignal.add(vSignalExpected))
  expect(afterSubgraph.nSignal).eq(beforeSubgraph.nSignal.add(nSignalExpected))
  expect(afterSubgraph.vSignal).eq(beforeVSignal.add(vSignalExpected))

  return tx
}

export const burnSignal = async (
  account: SignerWithAddress,
  subgraphID: string,
  gns: L1GNS | L2GNS,
  curation: Curation | L2Curation,
): Promise<ContractTransaction> => {
  // Before state
  const beforeSubgraph = await gns.subgraphs(subgraphID)
  const [beforeTokens, beforeVSignal] = await getTokensAndVSignal(
    beforeSubgraph.subgraphDeploymentID,
    curation,
  )
  const beforeUsersNSignal = await gns.getCuratorSignal(subgraphID, account.address)

  // Withdraw
  const { 0: vSignalExpected, 1: tokensExpected } = await gns.nSignalToTokens(
    subgraphID,
    beforeUsersNSignal,
  )

  // Send tx
  const tx = gns.connect(account).burnSignal(subgraphID, beforeUsersNSignal, 0)
  await expect(tx)
    .emit(gns, 'SignalBurned')
    .withArgs(subgraphID, account.address, beforeUsersNSignal, vSignalExpected, tokensExpected)

  // After state
  const afterSubgraph = await gns.subgraphs(subgraphID)
  const [afterTokens, afterVSignalCuration] = await getTokensAndVSignal(
    afterSubgraph.subgraphDeploymentID,
    curation,
  )

  // Check state
  expect(afterTokens).eq(beforeTokens.sub(tokensExpected))
  expect(afterVSignalCuration).eq(beforeVSignal.sub(vSignalExpected))
  expect(afterSubgraph.nSignal).eq(beforeSubgraph.nSignal.sub(beforeUsersNSignal))

  return tx
}

export const deprecateSubgraph = async (
  account: SignerWithAddress,
  subgraphID: string,
  gns: L1GNS | L2GNS,
  curation: Curation | L2Curation,
  grt: GraphToken | L2GraphToken,
) => {
  // Before state
  const beforeSubgraph = await gns.subgraphs(subgraphID)
  const [beforeTokens] = await getTokensAndVSignal(beforeSubgraph.subgraphDeploymentID, curation)

  // We can use the whole amount, since in this test suite all vSignal is used to be staked on nSignal
  const ownerBalanceBefore = await grt.balanceOf(account.address)

  // Send tx
  const tx = gns.connect(account).deprecateSubgraph(subgraphID)
  await expect(tx).emit(gns, 'SubgraphDeprecated').withArgs(subgraphID, beforeTokens)

  // After state
  const afterSubgraph = await gns.subgraphs(subgraphID)
  // Check marked as deprecated
  expect(afterSubgraph.disabled).eq(true)
  // Signal for the deployment must be all burned
  expect(afterSubgraph.vSignal.eq(toBN('0')))
  // Cleanup reserve ratio
  expect(afterSubgraph.__DEPRECATED_reserveRatio).eq(0)
  // Should be equal since owner pays curation tax
  expect(afterSubgraph.withdrawableGRT).eq(beforeTokens)

  // Check balance of GNS increased by curation tax from owner being added
  const afterGNSBalance = await grt.balanceOf(gns.address)
  expect(afterGNSBalance).eq(afterSubgraph.withdrawableGRT)
  // Check that the owner balance decreased by the curation tax
  const ownerBalanceAfter = await grt.balanceOf(account.address)
  expect(ownerBalanceBefore.eq(ownerBalanceAfter))

  // Check NFT was burned
  await expect(gns.ownerOf(subgraphID)).revertedWith('ERC721: owner query for nonexistent token')

  return tx
}

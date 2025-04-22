import { BytesLike, ethers } from 'ethers'
import { RAV } from './types'

export function encodeRegistrationData(url: string, geoHash: string, rewardsDestination: string) {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['string', 'string', 'address'],
    [url, geoHash, rewardsDestination],
  )
}

export function encodeStartServiceData(
  subgraphDeploymentId: string,
  allocationTokens: bigint,
  allocationId: string,
  signature: string,
) {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['bytes32', 'uint256', 'address', 'bytes'],
    [subgraphDeploymentId, allocationTokens, allocationId, signature],
  )
}

export function encodeCollectIndexingRewardsData(allocationId: string, poi: BytesLike) {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'bytes32'],
    [allocationId, poi],
  )
}

export function encodeCollectQueryFeesData(rav: RAV, signature: string) {
  // Encode the signed RAV
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['tuple(tuple(bytes32 collectionId, address payer, address serviceProvider, address dataService, uint256 timestampNs, uint128 valueAggregate, bytes metadata) rav, bytes signature)'],
    [{ rav, signature }],
  )
}

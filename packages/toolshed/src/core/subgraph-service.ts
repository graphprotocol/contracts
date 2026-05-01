import { BytesLike, ethers } from 'ethers'

import { RAV } from './types'

export function encodeRegistrationData(url: string, geoHash: string, rewardsDestination: string) {
  return ethers.AbiCoder.defaultAbiCoder().encode(['string', 'string', 'address'], [url, geoHash, rewardsDestination])
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

export function encodeCollectIndexingRewardsData(allocationId: string, poi: BytesLike, poiMetadata: BytesLike) {
  return ethers.AbiCoder.defaultAbiCoder().encode(['address', 'bytes32', 'bytes'], [allocationId, poi, poiMetadata])
}

export function encodeCollectQueryFeesData(rav: RAV, signature: string, tokensToCollect: bigint) {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    [
      'tuple(tuple(bytes32 collectionId, address payer, address serviceProvider, address dataService, uint64 timestampNs, uint128 valueAggregate, bytes metadata) rav, bytes signature)',
      'uint256',
    ],
    [{ rav, signature }, tokensToCollect],
  )
}

export function encodeCollectIndexingFeesData(
  agreementId: string,
  entities: bigint,
  poi: BytesLike,
  poiBlockNumber: bigint,
  metadata: BytesLike,
  maxSlippage: bigint,
) {
  const innerData = ethers.AbiCoder.defaultAbiCoder().encode(
    ['uint256', 'bytes32', 'uint256', 'bytes', 'uint256'],
    [entities, poi, poiBlockNumber, metadata, maxSlippage],
  )
  return ethers.AbiCoder.defaultAbiCoder().encode(['bytes16', 'bytes'], [agreementId, innerData])
}

export function encodeStopServiceData(allocationId: string) {
  return ethers.AbiCoder.defaultAbiCoder().encode(['address'], [allocationId])
}

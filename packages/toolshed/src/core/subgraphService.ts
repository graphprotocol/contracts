import { BytesLike, ethers } from 'ethers'

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
  signature: string
) {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['bytes32', 'uint256', 'address', 'bytes'],
    [subgraphDeploymentId, allocationTokens, allocationId, signature],
  )
}

export function encodeCollectData(allocationId: string, poi: BytesLike) {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'bytes32'],
    [allocationId, poi],
  )
}

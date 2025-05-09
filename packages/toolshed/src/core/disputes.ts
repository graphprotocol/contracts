import { ethers } from 'ethers'

// For disputes in the legacy dispute manager contract
export function generateLegacyIndexingDisputeId(allocationId: string) {
  return ethers.solidityPackedKeccak256(['address'], [allocationId])
}

export function generateLegacyQueryDisputeId(
  queryHash: string,
  responseHash: string,
  subgraphDeploymentId: string,
  indexer: string,
  fisherman: string,
) {
  return ethers.solidityPackedKeccak256(
    ['bytes32', 'bytes32', 'bytes32', 'address', 'address'],
    [queryHash, responseHash, subgraphDeploymentId, indexer, fisherman],
  )
}

// For legacy dispute type in dispute manager contract
export function generateLegacyTypeDisputeId(allocationId: string) {
  return ethers.solidityPackedKeccak256(
    ['address', 'string'],
    [allocationId, 'legacy']
  )
}

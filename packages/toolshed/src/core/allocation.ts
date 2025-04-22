import { ethers, id, keccak256, toUtf8Bytes } from 'ethers'
import { randomHexBytes } from '../lib/bytes'

// For legacy allocations in the staking contract
export async function generateLegacyAllocationProof(indexerAddress: string, allocationPrivateKey: string) {
  const wallet = new ethers.Wallet(allocationPrivateKey)
  const messageHash = ethers.solidityPackedKeccak256(
    ['address', 'address'],
    [indexerAddress, wallet.address],
  )
  const messageHashBytes = ethers.getBytes(messageHash)
  return wallet.signMessage(messageHashBytes)
}

export const EIP712_ALLOCATION_PROOF_TYPEHASH = id('AllocationIdProof(address indexer,address allocationId)')

export const EIP712_ALLOCATION_ID_PROOF_TYPES = {
  AllocationIdProof: [
    { name: 'indexer', type: 'address' },
    { name: 'allocationId', type: 'address' },
  ],
}

// For new allocations in the subgraph service
export async function generateAllocationProof(
  indexerAddress: string,
  allocationPrivateKey: string,
  subgraphServiceAddress: string,
  chainId: number,
) {
  const wallet = new ethers.Wallet(allocationPrivateKey)

  const domain = {
    name: 'SubgraphService',
    version: '1.0',
    chainId: chainId,
    verifyingContract: subgraphServiceAddress,
  }

  return wallet.signTypedData(domain, EIP712_ALLOCATION_ID_PROOF_TYPES, {
    indexer: indexerAddress,
    allocationId: wallet.address,
  })
}

export function randomAllocationMetadata() {
  return randomHexBytes(32)
}

export function generatePOI() {
  return ethers.getBytes(keccak256(toUtf8Bytes('poi')))
}
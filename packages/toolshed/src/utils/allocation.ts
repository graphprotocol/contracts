import { ethers } from 'ethers'
import { randomHexBytes } from '../lib/bytes'

// Generate allocation proof with the indexer's address and the allocation id, signed by the allocation private key
export async function generateAllocationProof(indexerAddress: string, allocationPrivateKey: string) {
  const wallet = new ethers.Wallet(allocationPrivateKey)
  const messageHash = ethers.solidityPackedKeccak256(
    ['address', 'address'],
    [indexerAddress, wallet.address],
  )
  const messageHashBytes = ethers.getBytes(messageHash)
  return wallet.signMessage(messageHashBytes)
}

export function randomAllocationMetadata() {
  return randomHexBytes(32)
}

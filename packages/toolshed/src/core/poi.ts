import { ethers, keccak256, toUtf8Bytes } from 'ethers'

export function createPOIFromString(message: string) {
  return ethers.getBytes(keccak256(toUtf8Bytes(message)))
}

import { ethers, keccak256, toUtf8Bytes } from 'ethers'

export function generatePOI(message = 'poi') {
  return ethers.getBytes(keccak256(toUtf8Bytes(message)))
}

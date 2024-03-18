import { ethers } from 'ethers'
import { hexlify, randomBytes } from 'ethers/lib/utils'

export const randomHexBytes = (n = 32): string => hexlify(randomBytes(n))

export const base58ToHex = (base58: string): string => {
  return ethers.utils.hexlify(ethers.utils.base58.decode(base58))
}

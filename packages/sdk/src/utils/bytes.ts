import { hexlify, randomBytes } from 'ethers/lib/utils'

export const randomHexBytes = (n = 32): string => hexlify(randomBytes(n))

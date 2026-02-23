import { ethers } from 'ethers'

export const randomHexBytes = (n = 32): string => ethers.hexlify(ethers.randomBytes(n))

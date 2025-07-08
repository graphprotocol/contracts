import { keccak256 } from 'ethers/lib/utils'

export const hashHexString = (input: string): string => keccak256(`0x${input.replace(/^0x/, '')}`)

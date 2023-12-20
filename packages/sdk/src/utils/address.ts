import { getAddress } from 'ethers/lib/utils'
import { randomHexBytes } from './bytes'

export const randomAddress = (): string => getAddress(randomHexBytes(20))

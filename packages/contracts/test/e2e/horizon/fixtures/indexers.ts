import { BigNumber } from 'ethers'
import { parseEther } from 'ethers/lib/utils'

export interface Indexer {
  address: string
  stake: BigNumber
}

export const indexers: Indexer[] = [
  {
    address: '0x95cED938F7991cd0dFcb48F0a06a40FA1aF46EBC', // Hardhat account #5
    stake: parseEther('1000000'),
  },
  {
    address: '0x3E5e9111Ae8eB78Fe1CC3bb8915d5D461F3Ef9A9', // Hardhat account #6
    stake: parseEther('1000000'),
  },
]

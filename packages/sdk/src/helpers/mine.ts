import {
  mine as hardhatMine,
  mineUpTo as hardhatMineUpTo,
} from '@nomicfoundation/hardhat-network-helpers'

import type { BigNumber } from 'ethers'

export async function mine(
  blocks?: string | number | BigNumber,
  interval?: string | number | BigNumber,
): Promise<void> {
  return hardhatMine(blocks, { interval })
}

export async function mineUpTo(blockNumber: string | number | BigNumber): Promise<void> {
  return hardhatMineUpTo(blockNumber)
}

export async function setAutoMine(autoMine: boolean): Promise<void> {
  const hre = await import('hardhat')

  // This allows the dynamic import to work on both ts and js
  const network = hre.network ?? hre.default.network
  return network.provider.send('evm_setAutomine', [autoMine])
}

export async function setIntervalMining(interval: number): Promise<void> {
  const hre = await import('hardhat')

  // This allows the dynamic import to work on both ts and js
  const network = hre.network ?? hre.default.network
  return network.provider.send('evm_setIntervalMining', [interval])
}

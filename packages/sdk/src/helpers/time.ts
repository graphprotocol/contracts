import { time } from '@nomicfoundation/hardhat-network-helpers'

export async function latestBlock(): Promise<number> {
  return time.latestBlock()
}

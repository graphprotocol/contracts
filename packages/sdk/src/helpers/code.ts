import { setCode as hardhatSetCode } from '@nomicfoundation/hardhat-network-helpers'

export async function setCode(address: string, code: string): Promise<void> {
  return hardhatSetCode(address, code)
}

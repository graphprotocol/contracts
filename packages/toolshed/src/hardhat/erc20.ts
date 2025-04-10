import { toBeHex, zeroPadValue } from 'ethers/utils'
import { keccak256 } from 'ethers/crypto'

import type { Addressable } from 'ethers'
import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'

export async function setGRTBalance(
  provider: HardhatEthersProvider,
  tokenAddress: string | Addressable,
  userAddress: string | Addressable,
  balance: bigint | string | number,
): Promise<void> {
  await setERC20Balance(provider, tokenAddress, userAddress, balance, 52)
}

export async function setERC20Balance(
  provider: HardhatEthersProvider,
  tokenAddress: string | Addressable,
  userAddress: string | Addressable,
  balance: bigint | string | number,
  slot = 0,
): Promise<void> {
  if (typeof tokenAddress !== 'string') {
    tokenAddress = await tokenAddress.getAddress()
  }
  if (typeof userAddress !== 'string') {
    userAddress = await userAddress.getAddress()
  }
  const paddedAddress = zeroPadValue(userAddress, 32) // 32-byte padded user address
  const paddedSlot = zeroPadValue(toBeHex(slot), 32) // 32-byte padded slot index

  // Compute the storage key for the mapping: keccak256(paddedAddress ++ paddedSlot)
  const storageKey = keccak256(paddedAddress + paddedSlot.slice(2))

  // Pad the balance to 32 bytes
  const paddedValue = toBeHex(balance, 32)

  await provider.send('hardhat_setStorageAt', [
    tokenAddress,
    storageKey,
    paddedValue,
  ])
}

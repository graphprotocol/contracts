import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

const localNetworks = ['localhost', 'hardhat', 'localNetwork']

export function requireLocalNetwork(hre: HardhatRuntimeEnvironment) {
  if (!localNetworks.includes(hre.network.name)) {
    throw new Error(`Network ${hre.network.name} is not a local network.`)
  }
}

export async function warp(provider: HardhatEthersProvider, seconds: number) {
  await provider.send('evm_increaseTime', [seconds])
  await provider.send('evm_mine', [])
}

export async function mine(provider: HardhatEthersProvider, blocks: number) {
  await provider.send('evm_mine', [blocks])
}

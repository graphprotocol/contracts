import { HardhatRuntimeEnvironment } from 'hardhat/types'

const localNetworks = ['localhost', 'hardhat', 'localNetwork']

export function requireLocalNetwork(hre: HardhatRuntimeEnvironment) {
  if (!localNetworks.includes(hre.network.name)) {
    throw new Error(`Network ${hre.network.name} is not a local network.`)
  }
}

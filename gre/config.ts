import fs from 'fs'
import { providers } from 'ethers'

import { NetworkConfig, NetworksConfig } from 'hardhat/types/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types/runtime'
import { HttpNetworkConfig } from 'hardhat/types/config'

import { GraphRuntimeEnvironmentOptions } from './type-extensions'
import { GREPluginError } from './helpers/errors'
import GraphChains from './helpers/chains'

import debug from 'debug'
const log = debug('hardhat:graphprotocol:gre')

interface GREChainData {
  l1ChainId: number
  l2ChainId: number
  isHHL1: boolean
  isHHL2: boolean
}

interface GREProviderData {
  l1Provider: providers.JsonRpcProvider
  l2Provider: providers.JsonRpcProvider
}

interface GREGraphConfigData {
  l1GraphConfigPath: string | undefined
  l2GraphConfigPath: string | undefined
}

export function getAddressBookPath(
  hre: HardhatRuntimeEnvironment,
  opts: GraphRuntimeEnvironmentOptions,
): string {
  const addressBookPath = opts.addressBook ?? hre.config.graph.addressBook

  if (addressBookPath === undefined) {
    throw new GREPluginError(`Must set a an addressBook path!`)
  }

  if (!fs.existsSync(addressBookPath)) {
    throw new GREPluginError(`Address book not found: ${addressBookPath}`)
  }

  return addressBookPath
}

export function getChains(mainChainId: number | undefined): GREChainData {
  if (!GraphChains.isSupported(mainChainId)) {
    const supportedChains = GraphChains.chains.join(',')
    throw new GREPluginError(
      `Chain ${mainChainId} is not supported! Supported chainIds: ${supportedChains}.`,
    )
  }

  // If mainChainId is supported there is a supported counterpart chainId so both chains are not undefined

  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  mainChainId = mainChainId!

  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  const secondaryChainId = GraphChains.counterpart(mainChainId)!

  const isHHL1 = GraphChains.isL1(mainChainId)
  const isHHL2 = GraphChains.isL2(mainChainId)
  const l1ChainId = isHHL1 ? mainChainId : secondaryChainId
  const l2ChainId = isHHL2 ? mainChainId : secondaryChainId

  log(`Hardhat chain id: ${mainChainId}`)
  log(`L1 chain id: ${l1ChainId} - Is HHL1: ${isHHL1}`)
  log(`L2 chain id: ${l2ChainId} - Is HHL2: ${isHHL2}`)

  return {
    l1ChainId,
    l2ChainId,
    isHHL1,
    isHHL2,
  }
}

export function getProviders(
  hre: HardhatRuntimeEnvironment,
  l1ChainId: number,
  l2ChainId: number,
): GREProviderData {
  const l1Network = getNetworkByChainId(hre.config.networks, l1ChainId) as HttpNetworkConfig
  const l2Network = getNetworkByChainId(hre.config.networks, l2ChainId) as HttpNetworkConfig

  for (const network of [l1Network, l2Network]) {
    if (network === undefined || network.url === undefined) {
      throw new GREPluginError(`Must set a provider url for chain ${l1ChainId}!`)
    }
  }

  const l1Provider = new providers.JsonRpcProvider(l1Network.url)
  const l2Provider = new providers.JsonRpcProvider(l2Network.url)

  return {
    l1Provider,
    l2Provider,
  }
}

export function getGraphConfigPaths(
  hre: HardhatRuntimeEnvironment,
  opts: GraphRuntimeEnvironmentOptions,
  l1ChainId: number,
  l2ChainId: number,
  isHHL1: boolean,
): GREGraphConfigData {
  const l1Network = getNetworkByChainId(hre.config.networks, l1ChainId)
  const l2Network = getNetworkByChainId(hre.config.networks, l2ChainId)

  // Priority is as follows:
  // - hre.graph() init parameter l1GraphConfigPath/l2GraphConfigPath
  // - hre.graph() init parameter graphConfigPath (only for layer corresponding to hh network)
  // - hh network config
  // - hh graph config (layer specific: l1GraphConfig, l2GraphConfig)
  const l1GraphConfigPath =
    opts.l1GraphConfig ??
    (isHHL1 ? opts.graphConfig : undefined) ??
    l1Network?.graphConfig ??
    hre.config.graph.l1GraphConfig

  const l2GraphConfigPath =
    opts.l2GraphConfig ??
    (!isHHL1 ? opts.graphConfig : undefined) ??
    l2Network?.graphConfig ??
    hre.config.graph.l2GraphConfig

  for (const configPath of [l1GraphConfigPath, l2GraphConfigPath]) {
    if (configPath !== undefined && !fs.existsSync(configPath)) {
      throw new GREPluginError(`Graph config file not found: ${configPath}`)
    }
  }

  return {
    l1GraphConfigPath: l1GraphConfigPath,
    l2GraphConfigPath: l2GraphConfigPath,
  }
}

function getNetworkByChainId(networks: NetworksConfig, chainId: number): NetworkConfig | undefined {
  return Object.keys(networks)
    .map((n) => networks[n])
    .find((n) => n.chainId === chainId)
}

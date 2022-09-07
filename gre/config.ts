import fs from 'fs'
import path from 'path'

import { NetworkConfig, NetworksConfig } from 'hardhat/types/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types/runtime'
import { HttpNetworkConfig } from 'hardhat/types/config'

import { GraphRuntimeEnvironmentOptions } from './type-extensions'
import { GREPluginError } from './helpers/error'
import GraphNetwork, { counterpartName } from './helpers/network'

import { createProvider } from 'hardhat/internal/core/providers/construction'
import { EthersProviderWrapper } from '@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper'

import { logDebug, logWarn } from './logger'
import { HARDHAT_NETWORK_NAME } from 'hardhat/plugins'

interface GREChains {
  l1ChainId: number
  l2ChainId: number
  isHHL1: boolean
  isHHL2: boolean
}

interface GREProviders {
  l1Provider: EthersProviderWrapper | undefined
  l2Provider: EthersProviderWrapper | undefined
}

interface GREGraphConfigs {
  l1GraphConfigPath: string | undefined
  l2GraphConfigPath: string | undefined
}

export function getAddressBookPath(
  hre: HardhatRuntimeEnvironment,
  opts: GraphRuntimeEnvironmentOptions,
): string {
  logDebug('== Getting address book path')
  logDebug(`Graph base dir: ${hre.config.paths.graph}`)
  logDebug(`1) opts.addressBookPath: ${opts.addressBook}`)
  logDebug(`2) hre.config.graph.addressBook: ${hre.config.graph?.addressBook}`)

  let addressBookPath = opts.addressBook ?? hre.config.graph?.addressBook

  if (addressBookPath === undefined) {
    throw new GREPluginError('Must set a an addressBook path!')
  }

  addressBookPath = normalizePath(addressBookPath, hre.config.paths.graph)

  if (!fs.existsSync(addressBookPath)) {
    throw new GREPluginError(`Address book not found: ${addressBookPath}`)
  }

  logDebug(`Address book path found: ${addressBookPath}`)
  return addressBookPath
}

export function getChains(mainChainId: number | undefined): GREChains {
  logDebug('== Getting chain ids')
  logDebug(`Hardhat chain id: ${mainChainId}`)

  if (!GraphNetwork.isSupported(mainChainId)) {
    throw new GREPluginError(`Chain ${mainChainId} is not supported!`)
  }

  // If mainChainId is supported there is a supported counterpart chainId so both chains are not undefined
  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  mainChainId = mainChainId!

  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  const secondaryChainId = GraphNetwork.counterpart(mainChainId)!
  logDebug(`Secondary chain id: ${secondaryChainId}`)

  const isHHL1 = GraphNetwork.isL1(mainChainId)
  const isHHL2 = GraphNetwork.isL2(mainChainId)
  const l1ChainId = isHHL1 ? mainChainId : secondaryChainId
  const l2ChainId = isHHL2 ? mainChainId : secondaryChainId

  logDebug(`L1 chain id: ${l1ChainId} - Is HHL1: ${isHHL1}`)
  logDebug(`L2 chain id: ${l2ChainId} - Is HHL2: ${isHHL2}`)

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
  isHHL1: boolean,
): GREProviders {
  logDebug('== Getting providers')

  const getProvider = (
    networks: NetworksConfig,
    chainId: number,
    mainNetworkName: string,
    isMainProvider: boolean,
    chainLabel: string,
  ): EthersProviderWrapper | undefined => {
    const network = getNetworkConfig(networks, chainId, mainNetworkName) as HttpNetworkConfig
    const networkName = getNetworkName(networks, chainId, mainNetworkName)

    logDebug(`Provider url for ${chainLabel}(${networkName}): ${network?.url}`)

    // Ensure at least main provider is configured
    // For Hardhat network we don't need url to create a provider
    if (
      isMainProvider &&
      (network === undefined || network.url === undefined) &&
      networkName !== HARDHAT_NETWORK_NAME
    ) {
      throw new GREPluginError(`Must set a provider url for chain: ${chainId}!`)
    }

    if (network === undefined || networkName === undefined) {
      return undefined
    }

    // Build provider as EthersProviderWrapper instead of JsonRpcProvider
    // This allows us to use hardhat's account management methods for free
    const ethereumProvider = createProvider(networkName, network)
    const ethersProviderWrapper = new EthersProviderWrapper(ethereumProvider)
    return ethersProviderWrapper
  }

  const l1Provider = getProvider(hre.config.networks, l1ChainId, hre.network.name, isHHL1, 'L1')
  const l2Provider = getProvider(hre.config.networks, l2ChainId, hre.network.name, !isHHL1, 'L2')

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
): GREGraphConfigs {
  logDebug('== Getting graph config paths')
  logDebug(`Graph base dir: ${hre.config.paths.graph}`)

  const l1Network = getNetworkConfig(hre.config.networks, l1ChainId, hre.network.name)
  const l2Network = getNetworkConfig(hre.config.networks, l2ChainId, hre.network.name)

  // Priority is as follows:
  // - hre.graph() init parameter l1GraphConfigPath/l2GraphConfigPath
  // - hre.graph() init parameter graphConfigPath (only for layer corresponding to hh network)
  // - hh network config
  // - hh graph config (layer specific: l1GraphConfig, l2GraphConfig)
  let l1GraphConfigPath =
    opts.l1GraphConfig ??
    (isHHL1 ? opts.graphConfig : undefined) ??
    l1Network?.graphConfig ??
    hre.config.graph.l1GraphConfig

  logDebug(`> L1 graph config`)
  logDebug(`1) opts.l1GraphConfig: ${opts.l1GraphConfig}`)
  logDebug(`2) opts.graphConfig: ${isHHL1 ? opts.graphConfig : undefined}`)
  logDebug(`3) l1Network.graphConfig: ${l1Network?.graphConfig}`)
  logDebug(`4) hre.config.graph.l1GraphConfig: ${hre.config.graph.l1GraphConfig}`)

  if (isHHL1 && l1GraphConfigPath === undefined) {
    throw new GREPluginError('Must specify a graph config file for L1!')
  }

  if (l1GraphConfigPath !== undefined) {
    l1GraphConfigPath = normalizePath(l1GraphConfigPath, hre.config.paths.graph)
  }

  let l2GraphConfigPath =
    opts.l2GraphConfig ??
    (!isHHL1 ? opts.graphConfig : undefined) ??
    l2Network?.graphConfig ??
    hre.config.graph.l2GraphConfig

  logDebug(`> L2 graph config`)
  logDebug(`1) opts.l2GraphConfig: ${opts.l2GraphConfig}`)
  logDebug(`2) opts.graphConfig: ${!isHHL1 ? opts.graphConfig : undefined}`)
  logDebug(`3) l2Network.graphConfig: ${l2Network?.graphConfig}`)
  logDebug(`4) hre.config.graph.l2GraphConfig: ${hre.config.graph.l2GraphConfig}`)

  if (!isHHL1 && l2GraphConfigPath === undefined) {
    throw new GREPluginError('Must specify a graph config file for L2!')
  }

  if (l2GraphConfigPath !== undefined) {
    l2GraphConfigPath = normalizePath(l2GraphConfigPath, hre.config.paths.graph)
  }

  for (const configPath of [l1GraphConfigPath, l2GraphConfigPath]) {
    if (configPath !== undefined && !fs.existsSync(configPath)) {
      throw new GREPluginError(`Graph config file not found: ${configPath}`)
    }
  }

  logDebug(`L1 graph config path: ${l1GraphConfigPath}`)
  logDebug(`L2 graph config path: ${l2GraphConfigPath}`)

  return {
    l1GraphConfigPath: l1GraphConfigPath,
    l2GraphConfigPath: l2GraphConfigPath,
  }
}

function getNetworkConfig(
  networks: NetworksConfig,
  chainId: number,
  mainNetworkName: string,
): (NetworkConfig & { name: string }) | undefined {
  const candidateNetworks = Object.keys(networks)
    .map((n) => ({ ...networks[n], name: n }))
    .filter((n) => n.chainId === chainId)

  if (candidateNetworks.length > 1) {
    logWarn(
      `Found multiple networks with chainId ${chainId}, trying to use main network name to desambiguate`,
    )

    const filteredByMainNetworkName = candidateNetworks.filter((n) => n.name === mainNetworkName)

    if (filteredByMainNetworkName.length === 1) {
      logDebug(`Found network with chainId ${chainId} and name ${mainNetworkName}`)
      return filteredByMainNetworkName[0]
    } else {
      logWarn(`Could not desambiguate with main network name, trying secondary network name`)
      const secondaryNetworkName = counterpartName(mainNetworkName)
      const filteredBySecondaryNetworkName = candidateNetworks.filter(
        (n) => n.name === secondaryNetworkName,
      )

      if (filteredBySecondaryNetworkName.length === 1) {
        logDebug(`Found network with chainId ${chainId} and name ${mainNetworkName}`)
        return filteredBySecondaryNetworkName[0]
      } else {
        throw new GREPluginError(
          `Could not desambiguate network with chainID ${chainId}. Use case not supported!`,
        )
      }
    }
  } else if (candidateNetworks.length === 1) {
    return candidateNetworks[0]
  } else {
    return undefined
  }
}

export function getNetworkName(
  networks: NetworksConfig,
  chainId: number,
  mainNetworkName: string,
): string | undefined {
  const network = getNetworkConfig(networks, chainId, mainNetworkName)
  return network?.name
}

function normalizePath(_path: string, graphPath: string) {
  if (!path.isAbsolute(_path)) {
    _path = path.join(graphPath, _path)
  }
  return _path
}

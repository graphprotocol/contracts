import { HardhatConfig, HardhatRuntimeEnvironment, HardhatUserConfig } from 'hardhat/types'
import { extendConfig, extendEnvironment } from 'hardhat/config'
import { lazyFunction, lazyObject } from 'hardhat/plugins'

import { getAddressBook } from '../cli/address-book'
import { loadContracts } from '../cli/contracts'
import { readConfig } from '../cli/config'
import {
  GraphNetworkEnvironment,
  GraphRuntimeEnvironment,
  GraphRuntimeEnvironmentOptions,
} from './type-extensions'
import { getChains, getProviders, getAddressBookPath, getGraphConfigPaths } from './config'
import { getDeployer, getNamedAccounts, getTestAccounts } from './accounts'
import { logDebug, logWarn } from './logger'
import path from 'path'
import { EthersProviderWrapper } from '@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper'

// Graph Runtime Environment (GRE) extensions for the HRE

extendConfig((config: HardhatConfig, userConfig: Readonly<HardhatUserConfig>) => {
  // Source for the path convention:
  // https://github.com/NomicFoundation/hardhat-ts-plugin-boilerplate/blob/d450d89f4b6ed5d26a8ae32b136b9c55d2aadab5/src/index.ts
  const userPath = userConfig.paths?.graph

  let newPath: string
  if (userPath === undefined) {
    newPath = config.paths.root
  } else {
    if (path.isAbsolute(userPath)) {
      newPath = userPath
    } else {
      newPath = path.normalize(path.join(config.paths.root, userPath))
    }
  }

  config.paths.graph = newPath
})

extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  hre.graph = (opts: GraphRuntimeEnvironmentOptions = {}) => {
    logDebug('*** Initializing Graph Runtime Environment (GRE) ***')
    logDebug(`Main network: ${hre.network.name}`)

    const { l1ChainId, l2ChainId, isHHL1 } = getChains(hre.network.config.chainId)
    const { l1Provider, l2Provider } = getProviders(hre, l1ChainId, l2ChainId, isHHL1)
    const addressBookPath = getAddressBookPath(hre, opts)
    const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
      hre,
      opts,
      l1ChainId,
      l2ChainId,
      isHHL1,
    )

    const l1Graph: GraphNetworkEnvironment | null = buildGraphNetworkEnvironment(
      l1ChainId,
      l1Provider,
      l1GraphConfigPath,
      addressBookPath,
      isHHL1,
    )

    const l2Graph: GraphNetworkEnvironment | null = buildGraphNetworkEnvironment(
      l2ChainId,
      l2Provider,
      l2GraphConfigPath,
      addressBookPath,
      isHHL1,
    )

    const gre: GraphRuntimeEnvironment = {
      ...(isHHL1 ? (l1Graph as GraphNetworkEnvironment) : (l2Graph as GraphNetworkEnvironment)),
      l1: l1Graph,
      l2: l2Graph,
    }

    logDebug('GRE initialized successfully!')
    logDebug(`Main network: L${isHHL1 ? '1' : '2'}`)
    logDebug(`Secondary network: ${gre.l2 !== null ? (isHHL1 ? 'L2' : 'L1') : 'not initialized'}`)
    return gre
  }
})

function buildGraphNetworkEnvironment(
  chainId: number,
  provider: EthersProviderWrapper | undefined,
  graphConfigPath: string | undefined,
  addressBookPath: string,
  isHHL1: boolean,
): GraphNetworkEnvironment | null {
  if (graphConfigPath === undefined) {
    logWarn(
      `No graph config file provided for chain: ${chainId}. ${
        isHHL1 ? 'L2' : 'L1'
      } will not be initialized.`,
    )
    return null
  }

  if (provider === undefined) {
    logWarn(
      `No provider URL found for: ${chainId}. ${isHHL1 ? 'L2' : 'L1'} will not be initialized.`,
    )
    return null
  }

  return {
    chainId: chainId,
    provider: provider,
    addressBook: lazyObject(() => getAddressBook(addressBookPath, chainId.toString())),
    graphConfig: lazyObject(() => readConfig(graphConfigPath, true)),
    contracts: lazyObject(() =>
      loadContracts(getAddressBook(addressBookPath, chainId.toString()), chainId, provider),
    ),
    getDeployer: lazyFunction(() => () => getDeployer(provider)),
    getNamedAccounts: lazyFunction(() => () => getNamedAccounts(provider, graphConfigPath)),
    getTestAccounts: lazyFunction(() => () => getTestAccounts(provider, graphConfigPath)),
  }
}

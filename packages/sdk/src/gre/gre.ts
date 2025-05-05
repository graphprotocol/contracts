import path from 'path'
import { Wallet } from 'ethers'
import { lazyFunction, lazyObject } from 'hardhat/plugins'
import { HardhatConfig, HardhatRuntimeEnvironment, HardhatUserConfig } from 'hardhat/types'
import { EthersProviderWrapper } from '@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper'

import { GraphNetworkAddressBook, readConfig, loadGraphNetworkContracts } from '..'
import {
  getAllAccounts,
  getDeployer,
  getNamedAccounts,
  getTestAccounts,
  getWallet,
  getWallets,
} from './accounts'
import { getAddressBookPath, getChains, getDefaultProviders, getGraphConfigPaths } from './config'
import { getSecureAccountsProvider } from './providers'
import { logDebug, logWarn } from './helpers/logger'
import { getDefaults } from '..'

import type {
  GraphNetworkEnvironment,
  GraphRuntimeEnvironment,
  GraphRuntimeEnvironmentOptions,
} from './types'

export const greExtendConfig = (config: HardhatConfig, userConfig: Readonly<HardhatUserConfig>) => {
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
}

export const greExtendEnvironment = (hre: HardhatRuntimeEnvironment) => {
  hre.graph = (opts: GraphRuntimeEnvironmentOptions = {}) => {
    logDebug('*** Initializing Graph Runtime Environment (GRE) ***')
    logDebug(`Main network: ${hre.network.name}`)

    logDebug('== Features')

    // Tx logging
    const enableTxLogging = opts.enableTxLogging ?? true
    logDebug(`Tx logging: ${enableTxLogging ? 'enabled' : 'disabled'}`)

    // Secure accounts
    const secureAccounts = !(
      opts.disableSecureAccounts ??
      hre.config.graph?.disableSecureAccounts ??
      false
    )
    logDebug(`Secure accounts: ${secureAccounts ? 'enabled' : 'disabled'}`)

    // Forking
    const fork = opts.fork ?? hre.config.graph?.fork ?? false
    logDebug(`Forking: ${fork ? 'enabled' : 'disabled'}`)

    if (fork && hre.network.config.accounts !== 'remote') {
      console.log(hre.network.config.accounts)

      logWarn('Forking is enabled but the network is not configured to use remote accounts')
    }

    const { l1ChainId, l2ChainId, isHHL1 } = getChains(hre.network.config.chainId)

    // Default providers for L1 and L2
    const { l1Provider, l2Provider } = getDefaultProviders(hre, l1ChainId, l2ChainId, isHHL1)

    // Getters to unlock secure account providers for L1 and L2
    const l1UnlockProvider = (caller: string) =>
      getSecureAccountsProvider(
        hre.accounts,
        hre.config.networks,
        l1ChainId,
        hre.network.name,
        isHHL1,
        'L1',
        caller,
        opts.l1AccountName,
        opts.l1AccountPassword,
      )

    const l2UnlockProvider = (caller: string) =>
      getSecureAccountsProvider(
        hre.accounts,
        hre.config.networks,
        l2ChainId,
        hre.network.name,
        !isHHL1,
        'L2',
        caller,
        opts.l2AccountName,
        opts.l2AccountPassword,
      )

    const addressBookPath = getAddressBookPath(hre, opts)
    const { l1GraphConfigPath, l2GraphConfigPath } = getGraphConfigPaths(
      hre,
      opts,
      l1ChainId,
      l2ChainId,
      isHHL1,
    )

    // Wallet functions
    const l1GetWallets = () => getWallets(hre.config.networks, l1ChainId, hre.network.name)
    const l1GetWallet = (address: string) =>
      getWallet(hre.config.networks, l1ChainId, hre.network.name, address)
    const l2GetWallets = () => getWallets(hre.config.networks, l2ChainId, hre.network.name)
    const l2GetWallet = (address: string) =>
      getWallet(hre.config.networks, l2ChainId, hre.network.name, address)

    // Build the Graph Runtime Environment (GRE)
    const l1Graph: GraphNetworkEnvironment | null = buildGraphNetworkEnvironment(
      l1ChainId,
      l1Provider,
      l1GraphConfigPath,
      addressBookPath,
      isHHL1,
      enableTxLogging,
      secureAccounts,
      fork,
      l1GetWallets,
      l1GetWallet,
      l1UnlockProvider,
    )

    const l2Graph: GraphNetworkEnvironment | null = buildGraphNetworkEnvironment(
      l2ChainId,
      l2Provider,
      l2GraphConfigPath,
      addressBookPath,
      isHHL1,
      enableTxLogging,
      secureAccounts,
      fork,
      l2GetWallets,
      l2GetWallet,
      l2UnlockProvider,
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
}

function buildGraphNetworkEnvironment(
  chainId: number,
  provider: EthersProviderWrapper | undefined,
  graphConfigPath: string | undefined,
  addressBookPath: string,
  isHHL1: boolean,
  enableTxLogging: boolean,
  secureAccounts: boolean,
  fork: boolean,
  getWallets: () => Promise<Wallet[]>,
  getWallet: (address: string) => Promise<Wallet>,
  unlockProvider: (caller: string) => Promise<EthersProviderWrapper>,
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

  // Upgrade provider to secure accounts if feature is enabled
  const getUpdatedProvider = async (caller: string) =>
    secureAccounts ? await unlockProvider(caller) : provider

  return {
    chainId: chainId,
    provider: provider,
    addressBook: lazyObject(() => new GraphNetworkAddressBook(addressBookPath, chainId)),
    graphConfig: lazyObject(() => {
      const config = readConfig(graphConfigPath, true)
      config.defaults = getDefaults(config, isHHL1)
      return config
    }),
    contracts: lazyObject(() =>
      loadGraphNetworkContracts(addressBookPath, chainId, provider, undefined, {
        enableTxLogging,
      }),
    ),
    getWallets: lazyFunction(() => () => getWallets()),
    getWallet: lazyFunction(() => (address: string) => getWallet(address)),
    getDeployer: lazyFunction(
      () => async () => getDeployer(await getUpdatedProvider('getDeployer')),
    ),
    getNamedAccounts: lazyFunction(
      () => async () =>
        getNamedAccounts(
          fork ? provider : await getUpdatedProvider('getNamedAccounts'),
          graphConfigPath,
        ),
    ),
    getTestAccounts: lazyFunction(
      () => async () =>
        getTestAccounts(await getUpdatedProvider('getTestAccounts'), graphConfigPath),
    ),
    getAllAccounts: lazyFunction(
      () => async () => getAllAccounts(await getUpdatedProvider('getAllAccounts')),
    ),
  }
}

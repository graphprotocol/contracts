import path from 'path'

import { GraphDeploymentsList, GraphRuntimeEnvironment, GraphRuntimeEnvironmentOptions, isGraphDeployment } from './types'
import { logDebug, logWarn } from './logger'
import { getAddressBookPath } from './config'
import { GraphHorizonAddressBook } from './sdk/deployments/horizon'
import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'

import type { HardhatConfig, HardhatRuntimeEnvironment, HardhatUserConfig } from 'hardhat/types'

export const greExtendConfig = (config: HardhatConfig, userConfig: Readonly<HardhatUserConfig>) => {
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

    const provider = new HardhatEthersProvider(hre.network.provider, hre.network.name)
    const deployments = [
      ...Object.keys(opts.addressBooks ?? {}),
      ...Object.keys(hre.network.config.addressBooks ?? {}),
      ...Object.keys(hre.config.graph?.addressBooks ?? {}),
    ]
    logDebug(`Detected deployments: ${deployments.join(', ')}`)

    // Build the Graph Runtime Environment (GRE) for each deployment
    const gre = {} as GraphRuntimeEnvironment
    for (const deployment of deployments) {
      if (!isGraphDeployment(deployment)) {
        logWarn(`Invalid deployment: ${deployment}. Skipping...`)
        continue
      }

      logDebug(`Initializing ${deployment} deployment...`)
      const addressBookPath = getAddressBookPath(deployment, hre, opts)
      let addressBook
      switch (deployment) {
        case 'horizon':
          addressBook = new GraphHorizonAddressBook(addressBookPath, hre.network.config.chainId!)
          gre.horizon = {
            addressBook: addressBook,
            contracts: addressBook.loadContracts(hre.network.config.chainId!, provider),
          }
          break

        default:
          break
      }
    }

    logDebug('GRE initialized successfully!')
    return gre
  }
}

// function buildGraphNetworkEnvironment(
//   chainId: number,
//   provider: EthersProviderWrapper | undefined,
//   graphConfigPath: string | undefined,
//   addressBookPath: string,
//   isHHL1: boolean,
//   enableTxLogging: boolean,
//   secureAccounts: boolean,
//   fork: boolean,
//   getWallets: () => Promise<Wallet[]>,
//   getWallet: (address: string) => Promise<Wallet>,
//   unlockProvider: (caller: string) => Promise<EthersProviderWrapper>,
// ): GraphNetworkEnvironment | null {
//   if (graphConfigPath === undefined) {
//     logWarn(
//       `No graph config file provided for chain: ${chainId}. ${
//         isHHL1 ? 'L2' : 'L1'
//       } will not be initialized.`,
//     )
//     return null
//   }

//   if (provider === undefined) {
//     logWarn(
//       `No provider URL found for: ${chainId}. ${isHHL1 ? 'L2' : 'L1'} will not be initialized.`,
//     )
//     return null
//   }

//   // Upgrade provider to secure accounts if feature is enabled
//   const getUpdatedProvider = async (caller: string) =>
//     secureAccounts ? await unlockProvider(caller) : provider

//   return {
//     chainId: chainId,
//     provider: provider,
//     addressBook: lazyObject(() => new GraphNetworkAddressBook(addressBookPath, chainId)),
//     graphConfig: lazyObject(() => {
//       const config = readConfig(graphConfigPath, true)
//       config.defaults = getDefaults(config, isHHL1)
//       return config
//     }),
//     contracts: lazyObject(() =>
//       loadGraphNetworkContracts(addressBookPath, chainId, provider, undefined, {
//         enableTxLogging,
//       }),
//     ),
//     getWallets: lazyFunction(() => () => getWallets()),
//     getWallet: lazyFunction(() => (address: string) => getWallet(address)),
//     getDeployer: lazyFunction(
//       () => async () => getDeployer(await getUpdatedProvider('getDeployer')),
//     ),
//     getNamedAccounts: lazyFunction(
//       () => async () =>
//         getNamedAccounts(
//           fork ? provider : await getUpdatedProvider('getNamedAccounts'),
//           graphConfigPath,
//         ),
//     ),
//     getTestAccounts: lazyFunction(
//       () => async () =>
//         getTestAccounts(await getUpdatedProvider('getTestAccounts'), graphConfigPath),
//     ),
//     getAllAccounts: lazyFunction(
//       () => async () => getAllAccounts(await getUpdatedProvider('getAllAccounts')),
//     ),
//   }
// }

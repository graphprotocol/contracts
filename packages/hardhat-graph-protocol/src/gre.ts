import path from 'path'

import { assertGraphRuntimeEnvironment } from './type-extensions'
import { getAddressBookPath } from './config'
import { GraphHorizonAddressBook } from './sdk/deployments/horizon'
import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import { isGraphDeployment } from './deployments'
import { logDebug } from './logger'

import type { HardhatConfig, HardhatRuntimeEnvironment, HardhatUserConfig } from 'hardhat/types'
import type { GraphRuntimeEnvironmentOptions } from './type-extensions'

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
  hre.graph = (opts: GraphRuntimeEnvironmentOptions = { deployments: {} }) => {
    logDebug('*** Initializing Graph Runtime Environment (GRE) ***')
    logDebug(`Main network: ${hre.network.name}`)
    const chainId = hre.network.config.chainId
    if (chainId === undefined) {
      throw new Error('Please define chainId in your Hardhat network configuration')
    }
    logDebug(`Chain Id: ${chainId}`)

    const deployments = [
      ...Object.keys(opts.deployments ?? {}),
      ...Object.keys(hre.network.config.deployments ?? {}),
      ...Object.keys(hre.config.graph?.deployments ?? {}),
    ].filter(v => isGraphDeployment(v))
    logDebug(`Detected deployments: ${deployments.join(', ')}`)

    // Build the Graph Runtime Environment (GRE) for each deployment
    const provider = new HardhatEthersProvider(hre.network.provider, hre.network.name)
    const greDeployments: Record<string, unknown> = {}
    for (const deployment of deployments) {
      logDebug(`== Initializing deployment: ${deployment} ==`)
      const addressBookPath = getAddressBookPath(deployment, hre, opts)
      let addressBook

      switch (deployment) {
        case 'horizon':
          addressBook = new GraphHorizonAddressBook(addressBookPath, chainId)
          greDeployments.horizon = {
            addressBook: addressBook,
            contracts: addressBook.loadContracts(provider),
          }
          break
        default:
          break
      }
    }

    const gre = {
      ...greDeployments,
      provider,
      chainId,
    }
    assertGraphRuntimeEnvironment(gre)
    logDebug('GRE initialized successfully!')
    return gre
  }
}

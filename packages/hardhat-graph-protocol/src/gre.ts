/* eslint-disable no-case-declarations */
import path from 'path'

import { loadGraphHorizon, loadSubgraphService } from '@graphprotocol/toolshed/deployments'
import { logDebug, logError } from './logger'
import { getAddressBookPath } from './config'
import { GraphPluginError } from './error'
import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import { isGraphDeployment } from './types'
import { lazyFunction } from 'hardhat/plugins'

import type { HardhatConfig, HardhatRuntimeEnvironment, HardhatUserConfig } from 'hardhat/types'
import type { GraphDeployments } from '@graphprotocol/toolshed/deployments'
import type { GraphRuntimeEnvironmentOptions } from './types'
import { getAccounts } from './accounts'

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
  hre.graph = lazyFunction(() => (opts: GraphRuntimeEnvironmentOptions = { deployments: {} }) => {
    logDebug('*** Initializing Graph Runtime Environment (GRE) ***')
    logDebug(`Main network: ${hre.network.name}`)
    const chainId = hre.network.config.chainId
    if (chainId === undefined) {
      throw new GraphPluginError('Please define chainId in your Hardhat network configuration')
    }
    logDebug(`Chain Id: ${chainId}`)

    const deployments = [...new Set([
      ...Object.keys(opts.deployments ?? {}),
      ...Object.keys(hre.network.config.deployments ?? {}),
      ...Object.keys(hre.config.graph?.deployments ?? {}),
    ].filter(v => isGraphDeployment(v)))]
    logDebug(`Detected deployments: ${deployments.join(', ')}`)

    // Build the Graph Runtime Environment (GRE) for each deployment
    const provider = new HardhatEthersProvider(hre.network.provider, hre.network.name)
    const greDeployments: GraphDeployments = {} as GraphDeployments

    for (const deployment of deployments) {
      logDebug(`== Initializing deployment: ${deployment} ==`)

      const addressBookPath = getAddressBookPath(deployment, hre, opts)
      if (addressBookPath === undefined) {
        logError(`Skipping deployment ${deployment} - Reason: address book path does not exist`)
        continue
      }

      try {
        switch (deployment) {
          case 'horizon':
            greDeployments.horizon = loadGraphHorizon(addressBookPath, chainId, provider)
            break
          case 'subgraphService':
            greDeployments.subgraphService = loadSubgraphService(addressBookPath, chainId, provider)
            break
          default:
            // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
            logError(`Skipping deployment ${deployment} - Reason: unknown deployment`)
            break
        }
      } catch (error) {
        logError(`Skipping deployment ${deployment} - Reason: runtime error`)
        logError(error)
        continue
      }
    }

    // Accounts
    const accounts = getAccounts(provider, chainId, greDeployments.horizon?.contracts?.GraphToken?.target)

    logDebug('GRE initialized successfully!')

    return {
      ...greDeployments,
      provider,
      chainId,
      accounts,
    }
  })
}

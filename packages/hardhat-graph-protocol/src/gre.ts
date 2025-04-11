/* eslint-disable no-case-declarations */
import path from 'path'

import {
  getAccounts,
  getArbitrator,
  getDeployer,
  getGateway,
  getGovernor,
  getPauseGuardian,
  getSubgraphAvailabilityOracle,
  getTestAccounts,
} from '@graphprotocol/toolshed'
import { loadGraphHorizon, loadSubgraphService } from '@graphprotocol/toolshed/deployments'
import { getAddressBookPath } from './config'
import { GraphPluginError } from './error'
import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import { isGraphDeployment } from './types'
import { lazyFunction } from 'hardhat/plugins'
import { logDebug } from './logger'

import type { HardhatConfig, HardhatRuntimeEnvironment, HardhatUserConfig } from 'hardhat/types'
import type { GraphDeployments } from '@graphprotocol/toolshed/deployments'
import type { GraphRuntimeEnvironmentOptions } from './types'

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
      switch (deployment) {
        case 'horizon':
          greDeployments.horizon = loadGraphHorizon(addressBookPath, chainId, provider)
          break
        case 'subgraphService':
          greDeployments.subgraphService = loadSubgraphService(addressBookPath, chainId, provider)
          break
        default:
          break
      }
    }

    logDebug('GRE initialized successfully!')
    return {
      ...greDeployments,
      provider,
      chainId,
      accounts: {
        getAccounts: async () => getAccounts(provider),
        getDeployer: async (accountIndex?: number) => getDeployer(provider, accountIndex),
        getGovernor: async (accountIndex?: number) => getGovernor(provider, accountIndex),
        getArbitrator: async (accountIndex?: number) => getArbitrator(provider, accountIndex),
        getPauseGuardian: async (accountIndex?: number) => getPauseGuardian(provider, accountIndex),
        getSubgraphAvailabilityOracle: async (accountIndex?: number) => getSubgraphAvailabilityOracle(provider, accountIndex),
        getGateway: async (accountIndex?: number) => getGateway(provider, accountIndex),
        getTestAccounts: async () => getTestAccounts(provider),
      },
    }
  })
}

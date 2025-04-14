import path from 'path'

import { GraphPluginError } from './error'
import { logDebug } from './logger'

import type { GraphDeploymentName } from '@graphprotocol/toolshed/deployments'
import type { GraphRuntimeEnvironmentOptions } from './types'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

export function getAddressBookPath(
  deployment: GraphDeploymentName,
  hre: HardhatRuntimeEnvironment,
  opts: GraphRuntimeEnvironmentOptions,
): string {
  const optsPath = getPath(opts.deployments?.[deployment])
  const networkPath = getPath(hre.network.config.deployments?.[deployment])
  const globalPath = getPath(hre.config.graph?.deployments?.[deployment])

  logDebug(`Getting address book path...`)
  logDebug(`Graph base dir: ${hre.config.paths.graph}`)
  logDebug(`1) opts: ${optsPath}`)
  logDebug(`2) network: ${networkPath}`)
  logDebug(`3) global: ${globalPath}`)

  const addressBookPath = optsPath ?? networkPath ?? globalPath
  if (addressBookPath === undefined) {
    throw new GraphPluginError('Must set a an addressBook path!')
  }

  const normalizedAddressBookPath = normalizePath(addressBookPath, hre.config.paths.graph)
  logDebug(`Address book path: ${normalizedAddressBookPath}`)
  return normalizedAddressBookPath
}

function normalizePath(_path: string, graphPath?: string): string {
  if (!path.isAbsolute(_path) && graphPath !== undefined) {
    _path = path.join(graphPath, _path)
  }
  return _path
}

function getPath(value: string | {
  addressBook: string
} | undefined): string | undefined {
  if (typeof value === 'string') {
    return value
  } else if (value && typeof value == 'object') {
    return value.addressBook
  }
  return
}

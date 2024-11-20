import fs from 'fs'
import { GraphPluginError } from './sdk/utils/error'
import { logDebug } from './logger'

import type { GraphDeployment, GraphRuntimeEnvironmentOptions } from './types'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import { normalizePath } from './sdk/utils/path'

export function getAddressBookPath(
  deployment: GraphDeployment,
  hre: HardhatRuntimeEnvironment,
  opts: GraphRuntimeEnvironmentOptions,
): string {
  logDebug(`== ${deployment} - Getting address book path`)
  logDebug(`Graph base dir: ${hre.config.paths.graph}`)
  logDebug(`1) opts.addressBooks.[deployment]: ${opts.addressBooks?.[deployment]}`)
  logDebug(`2) hre.network.config.addressBooks.[deployment]: ${hre.network.config?.addressBooks?.[deployment]}`)
  logDebug(`3) hre.config.graph.addressBooks.[deployment]: ${hre.config.graph?.addressBooks?.[deployment]}`)

  let addressBookPath
    = opts.addressBooks?.[deployment] ?? hre.network.config?.addressBooks?.[deployment] ?? hre.config.graph?.addressBooks?.[deployment]

  if (addressBookPath === undefined) {
    throw new GraphPluginError('Must set a an addressBook path!')
  }

  addressBookPath = normalizePath(addressBookPath, hre.config.paths.graph)

  if (!fs.existsSync(addressBookPath)) {
    throw new GraphPluginError(`Address book not found: ${addressBookPath}`)
  }

  logDebug(`Address book path found: ${addressBookPath}`)
  return addressBookPath
}

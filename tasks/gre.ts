import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { extendEnvironment } from 'hardhat/config'
import { lazyObject } from 'hardhat/plugins'

import { getAddressBook } from '../cli/address-book'
import { loadContracts } from '../cli/contracts'
import { readConfig } from '../cli/config'
import { GREOptions } from './type-extensions'
import fs from 'fs'

// Graph Runtime Environment (GRE) extensions for the HRE
extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  hre.graph = (opts: GREOptions = {}) => {
    const chainId = hre.network.config.chainId?.toString() ?? '1337'
    const addressBookPath = opts.addressBook ?? process.env.ADDRESS_BOOK
    const graphConfigPath = opts.graphConfig ?? process.env.GRAPH_CONFIG

    if (!fs.existsSync(addressBookPath)) {
      throw new Error(`Address book not found: ${addressBookPath}`)
    }

    if (!fs.existsSync(graphConfigPath)) {
      throw new Error(`Graph config not found: ${graphConfigPath}`)
    }

    return {
      addressBook: lazyObject(() => getAddressBook(addressBookPath, chainId)),
      graphConfig: lazyObject(() => readConfig(graphConfigPath, true)),
      contracts: lazyObject(() =>
        loadContracts(getAddressBook(addressBookPath, chainId), chainId, hre.ethers.provider),
      ),
    }
  }
})

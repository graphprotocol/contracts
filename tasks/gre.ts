import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { extendEnvironment } from 'hardhat/config'
import { lazyObject } from 'hardhat/plugins'

import { cliOpts } from '../cli/defaults'
import { getAddressBook } from '../cli/address-book'
import { loadContracts } from '../cli/contracts'
import { readConfig } from '../cli/config'

// Graph Runtime Environment (GRE) extensions for the HRE
extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  const chainId = hre.network.config.chainId?.toString() ?? '1337'

  // hre converts user defined task argvs into env variables
  const addressBookPath = process.env.ADDRESS_BOOK ?? cliOpts.addressBook.default // --address-book
  const graphConfigPath = process.env.GRAPH_CONFIG ?? cliOpts.graphConfig.default // --graph-config

  hre.graph = {
    addressBook: lazyObject(() => getAddressBook(addressBookPath, chainId)),
    graphConfig: lazyObject(() => readConfig(graphConfigPath, true)),
    contracts: lazyObject(() => loadContracts(hre.graph.addressBook, hre.ethers.provider)),
  }
})

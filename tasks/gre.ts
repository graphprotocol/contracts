import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { extendEnvironment } from 'hardhat/config'
import { lazyObject } from 'hardhat/plugins'
import '@nomiclabs/hardhat-ethers'

import { cliOpts } from '../cli/defaults'
import { getAddressBook } from '../cli/address-book'
import { loadContracts, NetworkContracts } from '../cli/contracts'

// Graph Runtime Environment (GRE) extensions for the HRE

declare module 'hardhat/types/runtime' {
  export interface HardhatRuntimeEnvironment {
    contracts: NetworkContracts
  }
}

extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  hre['contracts'] = lazyObject(() => {
    const addressBook = getAddressBook(
      cliOpts.addressBook.default,
      hre.network.config.chainId.toString(),
    )
    return loadContracts(addressBook, hre.ethers.provider)
  })
})

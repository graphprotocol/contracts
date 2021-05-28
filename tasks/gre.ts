import { Contract, providers, Signer } from 'ethers'
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

interface ConsoleNetworkContracts extends NetworkContracts {
  connect: () => void
}

extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  hre['contracts'] = lazyObject(() => {
    const chainId = hre.network.config.chainId.toString()
    const provider = hre.ethers.provider
    const addressBook = getAddressBook(cliOpts.addressBook.default, chainId)
    const contracts = loadContracts(addressBook, provider) as ConsoleNetworkContracts

    // Connect contracts to a signing account
    contracts.connect = async function (n = 0) {
      const accounts = await hre.ethers.getSigners()
      const senderAccount = accounts[n]
      console.log(`> Sender set to ${senderAccount.address}`)
      for (const [k, contract] of Object.entries(contracts)) {
        if (contract instanceof Contract) {
          contracts[k] = contract.connect(senderAccount)
        }
      }
    }

    return contracts
  })
})

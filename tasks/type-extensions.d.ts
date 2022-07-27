import { AddressBook } from '../cli/address-book'
import { NetworkContracts } from '../cli/contracts'

interface GREOptions {
  addressBook?: string
  graphConfig?: string
}

declare module 'hardhat/types/runtime' {
  export interface HardhatRuntimeEnvironment {
    graph: (opts?: GREOptions) => {
      contracts: NetworkContracts
      graphConfig: any
      addressBook: AddressBook
    }
  }
}

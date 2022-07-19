import { AddressBook } from '../cli/address-book'
import { NetworkContracts } from '../cli/contracts'

declare module 'hardhat/types/runtime' {
  export interface HardhatRuntimeEnvironment {
    graph: {
      contracts: NetworkContracts
      graphConfig: any
      addressBook: AddressBook
    }
  }
}

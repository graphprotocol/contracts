import { Signer } from 'ethers'
import { AddressBook } from '../cli/address-book'
import { NetworkContracts } from '../cli/contracts'

export interface GREOptions {
  addressBook?: string
  graphConfig?: string
}

export interface Account {
  readonly signer: Signer
  readonly address: string
}

export interface NamedAccounts {
  arbitrator: Account
  governor: Account
  authority: Account
  availabilityOracle: Account
  pauseGuardian: Account
  allocationExchangeOwner: Account
}

declare module 'hardhat/types/runtime' {
  export interface HardhatRuntimeEnvironment {
    graph: (opts?: GREOptions) => {
      contracts: NetworkContracts
      graphConfig: any
      addressBook: AddressBook
      getNamedAccounts: () => Promise<NamedAccounts>
      getAccounts: () => Promise<Account[]>
      getDeployer: () => Promise<Account>
    }
  }
}

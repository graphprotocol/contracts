import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { AddressBook } from '../cli/address-book'
import { NetworkContracts } from '../cli/contracts'

export interface GREOptions {
  addressBook?: string
  graphConfig?: string
}

export interface NamedAccounts {
  arbitrator: SignerWithAddress
  governor: SignerWithAddress
  authority: SignerWithAddress
  availabilityOracle: SignerWithAddress
  pauseGuardian: SignerWithAddress
  allocationExchangeOwner: SignerWithAddress
}

declare module 'hardhat/types/runtime' {
  export interface HardhatRuntimeEnvironment {
    graph: (opts?: GREOptions) => {
      contracts: NetworkContracts
      graphConfig: any
      addressBook: AddressBook
      getNamedAccounts: () => Promise<NamedAccounts>
<<<<<<< HEAD
      getTestAccounts: () => Promise<SignerWithAddress[]>
      getDeployer: () => Promise<SignerWithAddress>
=======
      getTestAccounts: () => Promise<Account[]>
      getDeployer: () => Promise<Account>
>>>>>>> 6e68b48 (feat: replace getAccounts with getTestAccounts)
    }
  }
}

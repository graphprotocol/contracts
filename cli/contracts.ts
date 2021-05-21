import { providers, Signer } from 'ethers'

import { AddressBook } from './address-book'
import { logger } from './logging'
import { getContractAt } from './network'

import { EpochManager } from '../build/types/EpochManager'
import { DisputeManager } from '../build/types/DisputeManager'
import { Staking } from '../build/types/Staking'
import { ServiceRegistry } from '../build/types/ServiceRegistry'
import { Curation } from '../build/types/Curation'
import { RewardsManager } from '../build/types/RewardsManager'
import { GNS } from '../build/types/GNS'
import { GraphProxyAdmin } from '../build/types/GraphProxyAdmin'
import { GraphToken } from '../build/types/GraphToken'
import { Controller } from '../build/types/Controller'
import { BancorFormula } from '../build/types/BancorFormula'
import { IENS } from '../build/types/IENS'
import { IEthereumDIDRegistry } from '../build/types/IEthereumDIDRegistry'

export interface NetworkContracts {
  EpochManager: EpochManager
  DisputeManager: DisputeManager
  Staking: Staking
  ServiceRegistry: ServiceRegistry
  Curation: Curation
  RewardsManager: RewardsManager
  GNS: GNS
  GraphProxyAdmin: GraphProxyAdmin
  GraphToken: GraphToken
  Controller: Controller
  BancorFormula: BancorFormula
  IENS: IENS
  IEthereumDIDRegistry: IEthereumDIDRegistry
}

export const loadContracts = (
  addressBook: AddressBook,
  signerOrProvider?: Signer | providers.Provider,
): NetworkContracts => {
  const contracts = {}
  for (const contractName of addressBook.listEntries()) {
    const contractEntry = addressBook.getEntry(contractName)
    try {
      const contract = getContractAt(contractName, contractEntry.address)
      contracts[contractName] = contract
      if (signerOrProvider) {
        contracts[contractName] = contracts[contractName].connect(signerOrProvider)
      }
    } catch (err) {
      logger.warn(`Could not load contract ${contractName} - ${err.message}`)
    }
  }
  return contracts as NetworkContracts
}

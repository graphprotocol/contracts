import { BaseContract, providers, Signer } from 'ethers'

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
import { GraphGovernance } from '../build/types/GraphGovernance'
import { AllocationExchange } from '../build/types/AllocationExchange'
import { L1GraphTokenGateway } from '../build/types/L1GraphTokenGateway'
import { L2GraphToken } from '../build/types/L2GraphToken'
import { L2GraphTokenGateway } from '../build/types/L2GraphTokenGateway'
import { BridgeEscrow } from '../build/types/BridgeEscrow'
import { chainIdIsL2 } from './utils'
import { SubgraphNFT } from '../build/types/SubgraphNFT'
import { GraphCurationToken } from '../build/types/GraphCurationToken'
import { SubgraphNFTDescriptor } from '../build/types/SubgraphNFTDescriptor'
import { L1Reservoir } from '../build/types/L1Reservoir'

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
  GraphGovernance: GraphGovernance
  AllocationExchange: AllocationExchange
  L1GraphTokenGateway: L1GraphTokenGateway
  L1Reservoir: L1Reservoir
  BridgeEscrow: BridgeEscrow
  L2GraphToken: L2GraphToken
  L2GraphTokenGateway: L2GraphTokenGateway
  SubgraphNFT: SubgraphNFT
  SubgraphNFTDescriptor: SubgraphNFTDescriptor
  GraphCurationToken: GraphCurationToken
}

export const loadAddressBookContract = (
  contractName: string,
  addressBook: AddressBook,
  signerOrProvider?: Signer | providers.Provider,
): BaseContract => {
  const contractEntry = addressBook.getEntry(contractName)
  let contract = getContractAt(contractName, contractEntry.address)
  if (signerOrProvider) {
    contract = contract.connect(signerOrProvider)
  }
  return contract
}

export const loadContracts = (
  addressBook: AddressBook,
  chainId: number | string,
  signerOrProvider?: Signer | providers.Provider,
): NetworkContracts => {
  const contracts = {}
  for (const contractName of addressBook.listEntries()) {
    try {
      contracts[contractName] = loadAddressBookContract(contractName, addressBook, signerOrProvider)
      // On L2 networks, we alias L2GraphToken as GraphToken
      if (signerOrProvider && chainIdIsL2(chainId) && contractName == 'L2GraphToken') {
        contracts['GraphToken'] = contracts[contractName]
      }
    } catch (err) {
      logger.warn(`Could not load contract ${contractName} - ${err.message}`)
    }
  }
  return contracts as NetworkContracts
}

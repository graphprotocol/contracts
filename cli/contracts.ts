import { Contract, ContractFunction, ContractTransaction, providers, Signer } from 'ethers'
import { Provider } from '@ethersproject/providers'
import lodash from 'lodash'

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
import { SubgraphNFT } from '../build/types/SubgraphNFT'
import { GraphCurationToken } from '../build/types/GraphCurationToken'
import { SubgraphNFTDescriptor } from '../build/types/SubgraphNFTDescriptor'

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
  SubgraphNFT: SubgraphNFT
  SubgraphNFTDescriptor: SubgraphNFTDescriptor
  GraphCurationToken: GraphCurationToken
}

export const loadContracts = (
  addressBook: AddressBook,
  signerOrProvider?: Signer | providers.Provider,
  enableTXLogging = false,
): NetworkContracts => {
  const contracts = {}
  for (const contractName of addressBook.listEntries()) {
    const contractEntry = addressBook.getEntry(contractName)
    try {
      let contract = getContractAt(contractName, contractEntry.address)
      if (enableTXLogging) {
        contract.connect = getWrappedConnect(contract)
        contract = wrapCalls(contract)
      }
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

// Returns a contract connect function that wrapps contract calls with wrapCalls
function getWrappedConnect(
  contract: Contract,
): (signerOrProvider: string | Provider | Signer) => Contract {
  const call = contract.connect.bind(contract)
  const override = (signerOrProvider: string | Provider | Signer): Contract => {
    const connectedContract = call(signerOrProvider)
    connectedContract.connect = getWrappedConnect(connectedContract)
    return wrapCalls(connectedContract)
  }
  return override
}

// Returns a contract with wrapped calls
// The wrapper will run the tx, wait for confirmation and log the details
function wrapCalls(contract: Contract): Contract {
  const wrappedContract = lodash.cloneDeep(contract)

  for (const fn of Object.keys(contract.functions)) {
    const call: ContractFunction<ContractTransaction> = contract.functions[fn]
    const override = async (...args: Array<any>): Promise<ContractTransaction> => {
      // Make the call
      const tx = await call(...args)
      console.log(
        `> Sent transaction ${fn}: [${args}] \n  contract: ${contract.address}\n  txHash: ${tx.hash}`,
      )

      // Wait for confirmation
      const receipt = await contract.provider.waitForTransaction(tx.hash)
      receipt.status
        ? console.log(`Transaction succeeded: ${tx.hash}`)
        : console.log(`Transaction failed: ${tx.hash}`)
      return tx
    }

    wrappedContract.functions[fn] = override
    wrappedContract[fn] = override
  }

  return wrappedContract
}

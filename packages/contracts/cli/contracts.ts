import {
  BaseContract,
  Contract,
  ContractFunction,
  ContractReceipt,
  ContractTransaction,
  providers,
  Signer,
} from 'ethers'
import { Provider } from '@ethersproject/providers'
import lodash from 'lodash'
import fs from 'fs'

import { AddressBook } from './address-book'
import { chainIdIsL2 } from './cross-chain'
import { logger } from './logging'
import { getContractAt } from './network'

import { EpochManager } from '../build/types/EpochManager'
import { DisputeManager } from '../build/types/DisputeManager'
import { L1Staking } from '../build/types/L1Staking'
import { L2Staking } from '../build/types/L2Staking'
import { ServiceRegistry } from '../build/types/ServiceRegistry'
import { Curation } from '../build/types/Curation'
import { RewardsManager } from '../build/types/RewardsManager'
import { GNS } from '../build/types/GNS'
import { L1GNS } from '../build/types/L1GNS'
import { L2GNS } from '../build/types/L2GNS'
import { GraphProxyAdmin } from '../build/types/GraphProxyAdmin'
import { GraphToken } from '../build/types/GraphToken'
import { Controller } from '../build/types/Controller'
import { BancorFormula } from '../build/types/BancorFormula'
import { IENS } from '../build/types/IENS'
import { AllocationExchange } from '../build/types/AllocationExchange'
import { SubgraphNFT } from '../build/types/SubgraphNFT'
import { GraphCurationToken } from '../build/types/GraphCurationToken'
import { SubgraphNFTDescriptor } from '../build/types/SubgraphNFTDescriptor'
import { L1GraphTokenGateway } from '../build/types/L1GraphTokenGateway'
import { L2GraphToken } from '../build/types/L2GraphToken'
import { L2GraphTokenGateway } from '../build/types/L2GraphTokenGateway'
import { BridgeEscrow } from '../build/types/BridgeEscrow'
import { L2Curation } from '../build/types/L2Curation'
import { IL1Staking } from '../build/types/IL1Staking'
import { IL2Staking } from '../build/types/IL2Staking'
import { Interface } from 'ethers/lib/utils'
import { loadArtifact } from './artifacts'

class WrappedContract {
  // The meta-class properties
  [key: string]: ContractFunction | any
}
export interface NetworkContracts {
  EpochManager: EpochManager
  DisputeManager: DisputeManager
  Staking: IL1Staking | IL2Staking
  ServiceRegistry: ServiceRegistry
  Curation: Curation | L2Curation
  L2Curation: L2Curation
  RewardsManager: RewardsManager
  GNS: GNS | L1GNS | L2GNS
  GraphProxyAdmin: GraphProxyAdmin
  GraphToken: GraphToken
  Controller: Controller
  BancorFormula: BancorFormula
  IENS: IENS
  AllocationExchange: AllocationExchange
  SubgraphNFT: SubgraphNFT
  SubgraphNFTDescriptor: SubgraphNFTDescriptor
  GraphCurationToken: GraphCurationToken
  L1GraphTokenGateway: L1GraphTokenGateway
  BridgeEscrow: BridgeEscrow
  L2GraphToken: L2GraphToken
  L2GraphTokenGateway: L2GraphTokenGateway
  L1GNS: L1GNS
  L2GNS: L2GNS
  L1Staking: IL1Staking
  L2Staking: IL2Staking
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
  enableTXLogging = false,
): NetworkContracts => {
  const contracts = {}
  for (const contractName of addressBook.listEntries()) {
    const contractEntry = addressBook.getEntry(contractName)

    try {
      let contract = getContractAt(contractName, contractEntry.address)
      if (enableTXLogging) {
        contract.connect = getWrappedConnect(contract, contractName)
        contract = wrapCalls(contract, contractName)
      }
      if (contractName == 'L1Staking') {
        // Hack the contract into behaving like an IL1Staking
        const iface = new Interface(loadArtifact('IL1Staking').abi)
        contract = new Contract(contract.address, iface) as unknown as IL1Staking
      } else if (contractName == 'L2Staking') {
        // Hack the contract into behaving like an IL2Staking
        const iface = new Interface(loadArtifact('IL2Staking').abi)
        contract = new Contract(contract.address, iface) as unknown as IL2Staking
      }
      contracts[contractName] = contract

      if (signerOrProvider) {
        contracts[contractName] = contracts[contractName].connect(signerOrProvider)
      }

      // On L2 networks, we alias L2GraphToken as GraphToken
      if (chainIdIsL2(chainId) && contractName == 'L2GraphToken') {
        contracts['GraphToken'] = contracts[contractName]
      }
      if (signerOrProvider && chainIdIsL2(chainId) && contractName == 'L2GNS') {
        contracts['GNS'] = contracts[contractName]
      }
      if (signerOrProvider && chainIdIsL2(chainId) && contractName == 'L2Staking') {
        contracts['Staking'] = contracts[contractName]
      }
      if (signerOrProvider && chainIdIsL2(chainId) && contractName == 'L2Curation') {
        contracts['Curation'] = contracts[contractName]
      }
      if (signerOrProvider && !chainIdIsL2(chainId) && contractName == 'L1GNS') {
        contracts['GNS'] = contracts[contractName]
      }
      if (signerOrProvider && !chainIdIsL2(chainId) && contractName == 'L1Staking') {
        contracts['Staking'] = contracts[contractName]
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
  contractName: string,
): (signerOrProvider: string | Provider | Signer) => Contract {
  const call = contract.connect.bind(contract)
  const override = (signerOrProvider: string | Provider | Signer): Contract => {
    const connectedContract = call(signerOrProvider)
    connectedContract.connect = getWrappedConnect(connectedContract, contractName)
    return wrapCalls(connectedContract, contractName)
  }
  return override
}

// Returns a contract with wrapped calls
// The wrapper will run the tx, wait for confirmation and log the details
function wrapCalls(contract: Contract, contractName: string): Contract {
  const wrappedContract = lodash.cloneDeep(contract) as WrappedContract

  for (const fn of Object.keys(contract.functions)) {
    const call: ContractFunction<ContractTransaction> = contract.functions[fn]
    const override = async (...args: Array<any>): Promise<ContractTransaction> => {
      // Make the call
      const tx = await call(...args)
      logContractCall(tx, contractName, fn, args)

      // Wait for confirmation
      const receipt = await contract.provider.waitForTransaction(tx.hash)
      logContractReceipt(tx, receipt)
      return tx
    }

    wrappedContract.functions[fn] = override
    wrappedContract[fn] = override
  }

  return wrappedContract as Contract
}

function logContractCall(
  tx: ContractTransaction,
  contractName: string,
  fn: string,
  args: Array<any>,
) {
  const msg = []
  msg.push(`> Sent transaction ${contractName}.${fn}`)
  msg.push(`   sender: ${tx.from}`)
  msg.push(`   contract: ${tx.to}`)
  msg.push(`   params: [ ${args} ]`)
  msg.push(`   txHash: ${tx.hash}`)

  logToConsoleAndFile(msg)
}

function logContractReceipt(tx: ContractTransaction, receipt: ContractReceipt) {
  const msg = []
  msg.push(
    receipt.status ? `✔ Transaction succeeded: ${tx.hash}` : `✖ Transaction failed: ${tx.hash}`,
  )

  logToConsoleAndFile(msg)
}

function logToConsoleAndFile(msg: string[]) {
  const isoDate = new Date().toISOString()
  const fileName = `tx-${isoDate.substring(0, 10)}.log`

  msg.map((line) => {
    console.log(line)
    fs.appendFileSync(fileName, `[${isoDate}] ${line}\n`)
  })
}

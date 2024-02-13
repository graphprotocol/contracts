import { Contract, Signer, providers } from 'ethers'
import { AddressBook } from '../address-book'
import { loadArtifact } from '../deploy/artifacts'

import type { ContractList } from '../types/contract'
import { getWrappedConnect, wrapCalls } from './wrap'

/**
 * Loads a contract instance for a given contract name and address
 *
 * @param name Name of the contract
 * @param address Address of the contract
 * @param signerOrProvider Signer or provider to use
 * @returns the loaded contract
 */
export const loadContractAt = (
  name: string,
  address: string,
  artifactsPath?: string | string[],
  signerOrProvider?: Signer | providers.Provider,
): Contract => {
  return new Contract(address, loadArtifact(name, artifactsPath).abi, signerOrProvider)
}

/**
 * Loads a contract from an address book
 *
 * @param name Name of the contract
 * @param addressBook Address book to use
 * @param signerOrProvider Signer or provider to use
 * @param enableTxLogging Enable transaction logging to console and output file. Defaults to `true`
 * @param optional If true, the contract is optional and will not throw if it cannot be loaded
 * @returns the loaded contract
 *
 * @throws Error if the contract could not be loaded
 */
export function loadContract<ChainId extends number = number, ContractName extends string = string>(
  name: ContractName,
  addressBook: AddressBook<ChainId, ContractName>,
  artifactsPath: string | string[],
  signerOrProvider?: Signer | providers.Provider,
  enableTxLogging = true,
  preloadedContract?: Contract,
): Contract {
  const contractEntry = addressBook.getEntry(name)

  try {
    let contract = preloadedContract ?? loadContractAt(name, contractEntry.address, artifactsPath)

    if (enableTxLogging) {
      contract.connect = getWrappedConnect(contract, name)
      contract = wrapCalls(contract, name)
    }

    if (signerOrProvider) {
      contract = contract.connect(signerOrProvider)
    }

    return contract
  } catch (err: unknown) {
    if (err instanceof Error) {
      throw new Error(`Could not load contract ${name} - ${err.message}`)
    } else {
      throw new Error(`Could not load contract ${name}`)
    }
  }
}

/**
 * Loads all contracts from an address book
 *
 * @param addressBook Address book to use
 * @param signerOrProvider Signer or provider to use
 * @param enableTxLogging Enable transaction logging to console and output file. Defaults to `true`
 * @returns the loaded contracts
 */
export const loadContracts = <
  ChainId extends number = number,
  ContractName extends string = string,
>(
  addressBook: AddressBook<ChainId, ContractName>,
  artifactsPath: string | string[],
  signerOrProvider?: Signer | providers.Provider,
  enableTXLogging = true,
  optionalContractNames?: string[],
): ContractList<ContractName> => {
  const contracts = {} as ContractList<ContractName>
  for (const contractName of addressBook.listEntries()) {
    try {
      const contract = loadContract(
        contractName,
        addressBook,
        artifactsPath,
        signerOrProvider,
        enableTXLogging,
      )
      contracts[contractName] = contract
    } catch (error) {
      if (optionalContractNames?.includes(contractName)) {
        console.log(`Skipping optional contract ${contractName}`)
        continue
      } else {
        throw error
      }
    }
  }

  return contracts
}

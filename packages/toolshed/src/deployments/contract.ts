import { Contract, Provider, Signer } from 'ethers'
import { loadArtifact } from './artifact'
import { wrapTransactionCalls } from './tx-logging'

export type ContractList<T extends string = string> = Partial<Record<T, unknown>>

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
export function loadContract<ContractName extends string = string>(
  name: ContractName,
  address: string,
  artifactsPath: string | string[],
  signerOrProvider?: Signer | Provider,
): Contract {
  try {
    let contract = new Contract(address, loadArtifact(name, artifactsPath).abi, signerOrProvider)

    if (signerOrProvider) {
      contract = contract.connect(signerOrProvider) as Contract
    }

    contract = wrapTransactionCalls(contract, name)

    return contract
  } catch (err: unknown) {
    if (err instanceof Error) {
      throw new Error(`Could not load contract ${name} - ${err.message}`)
    } else {
      throw new Error(`Could not load contract ${name}`)
    }
  }
}

import lodash from 'lodash'

import type { Contract, ContractFunction, ContractTransaction, Signer } from 'ethers'
import type { Provider } from '@ethersproject/providers'
import type { ContractParam } from '../types/contract'
import { logContractCall, logContractReceipt } from './log'

class WrappedContract {
  // The meta-class properties
  [key: string]: ContractFunction | any
}

function isContractTransaction(call: ContractTransaction | any): call is ContractTransaction {
  return typeof call === 'object' && (call as ContractTransaction).hash !== undefined
}

/**
 * Modifies a contract connect function to return a contract wrapped with {@link wrapCalls}
 *
 * @param contract Contract to wrap
 * @param contractName Name of the contract
 * @returns the contract connect function
 */
export function getWrappedConnect(
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

/**
 * Wraps contract calls with a modified call function that logs the tx details
 *
 * @remarks
 * The override function will:
 * 1. Make the contract call
 * 2. Wait for tx confirmation using `provider.waitForTransaction()`
 * 3. Log the tx details and the receipt details, both to the console and to a file
 *
 * @param contract Contract to be wrapped
 * @param contractName Name of the contract
 * @returns the wrapped contract
 */
export function wrapCalls(contract: Contract, contractName: string): Contract {
  const wrappedContract = lodash.cloneDeep(contract) as WrappedContract

  for (const fn of Object.keys(contract.functions)) {
    const call = contract.functions[fn]
    const override = async (...args: Array<ContractParam>): Promise<ContractTransaction | any> => {
      const response = await call(...args)

      // If it's a read only call, return the response
      if (!isContractTransaction(response)) {
        return Array.isArray(response) && response.length === 1 ? response[0] : response
      }

      // Otherwise it's a tx, log the details
      logContractCall(response, contractName, fn, args)

      // And wait for confirmation
      const receipt = await contract.provider.waitForTransaction(response.hash)
      logContractReceipt(receipt)

      // Finally return the tx response
      return response
    }

    wrappedContract[fn] = override
    wrappedContract.functions[fn] = override
  }

  return wrappedContract as Contract
}

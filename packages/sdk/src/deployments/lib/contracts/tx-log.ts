import fs from 'fs'
import lodash from 'lodash'

import type {
  Contract,
  ContractFunction,
  ContractReceipt,
  ContractTransaction,
  Signer,
} from 'ethers'
import type { Provider } from '@ethersproject/providers'
import type { ContractParam } from '../types/contract'

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
  const wrappedContract = lodash.cloneDeep(contract)

  for (const fn of Object.keys(contract.functions)) {
    const call = contract.functions[fn]
    const override = async (...args: Array<ContractParam>): Promise<ContractTransaction> => {
      // Make the call
      const result = await call(...args)

      // logContractCall(tx, contractName, fn, args)

      // If there is a tx hash it's a tx, otherwise it's just a call
      // Wait for tx confirmation if it's a tx
      if (result.hash) {
        const receipt = await contract.provider.waitForTransaction(result.hash)
        // logContractReceipt(tx, receipt)
        return result
      } else {
        return result.length ? result[0] : result
      }
    }

    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    wrappedContract[fn] = override
    wrappedContract.functions[fn] = override
  }

  return wrappedContract
}

function logContractCall(
  tx: ContractTransaction,
  contractName: string,
  fn: string,
  args: Array<ContractParam>,
) {
  const msg: string[] = []
  msg.push(`> Sent transaction ${contractName}.${fn}`)
  msg.push(`   sender: ${tx.from}`)
  msg.push(`   contract: ${tx.to}`)
  msg.push(`   params: [ ${args} ]`)
  msg.push(`   txHash: ${tx.hash}`)

  logToConsoleAndFile(msg)
}

function logContractReceipt(tx: ContractTransaction, receipt: ContractReceipt) {
  const msg: string[] = []
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

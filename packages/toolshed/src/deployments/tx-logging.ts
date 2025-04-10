/* eslint-disable @typescript-eslint/no-explicit-any */
import fs from 'fs'

import { logDebug } from '../lib/logger'

import type {
  Contract,
  ContractMethod,
  ContractMethodArgs,
  ContractRunner,
  ContractTransactionReceipt,
  ContractTransactionResponse,
} from 'ethers'

/**
 * Wraps contract calls with a modified call function that logs the tx details
 * Also intercepts connect calls and wraps the returned contract with this function
 *
 * @remarks
 * The overriden functions will:
 * 1. Make the contract call
 * 2. Wait for tx confirmation
 * 3. Log the tx details and the receipt details, both to the console and to a file
 *
 * @param contract Contract to be wrapped
 * @param contractName Name of the contract
 * @returns the wrapped contract
 */
export function wrapTransactionCalls<T extends Contract>(contract: T, contractName: string): T {
  return new Proxy(contract, {
    get(target, prop) {
      const orig = Reflect.get(target, prop)

      // Intercept connect calls
      if (prop === 'connect') {
        return (runner: ContractRunner) => {
          const connected = orig.call(target, runner) as unknown as Contract
          return wrapTransactionCalls(connected, contractName)
        }
      }

      // Only intercept function calls
      if (typeof orig !== 'function') {
        return orig
      }

      // Only intercept function calls from the ABI
      let fn: ContractMethod<any[], any, any> | undefined
      try {
        fn = contract.getFunction(String(prop))
      } catch (_) {
        return orig
      }

      // Only intercept state changing calls - aka transactions
      const fragment = fn.fragment
      if (['view', 'pure'].includes(fragment.stateMutability)) {
        return orig
      }

      // Finally, this is a transaction call so intercept it :D
      return async (...args: unknown[]) => {
        // Make the call
        const response = await orig.apply(target, args) as ContractTransactionResponse
        logContractTransaction(response, contractName, String(prop), args)

        // And wait for confirmation
        const receipt = await response.wait()
        if (receipt) {
          logContractTransactionReceipt(receipt)
        }

        return response
      }
    },
  })
}

function logContractTransaction(
  tx: ContractTransactionResponse,
  contractName: string,
  fn: string,
  args: ContractMethodArgs<any>,
) {
  const msg: string[] = []
  msg.push(`> Sending transaction: ${contractName}.${fn}`)
  msg.push(`   = Sender: ${tx.from}`)
  msg.push(`   = Contract: ${tx.to}`)
  msg.push(`   = Params: [ ${args.join(', ')} ]`)
  msg.push(`   = TxHash: ${tx.hash}`)

  logToConsoleAndFile(msg)
}

function logContractTransactionReceipt(receipt: ContractTransactionReceipt) {
  const msg: string[] = []
  msg.push(receipt.status ? `   ✔ Transaction succeeded!` : `   ✖ Transaction failed!`)
  logToConsoleAndFile(msg)
}

function logToConsoleAndFile(msg: string[]) {
  const isoDate = new Date().toISOString()
  const fileName = `tx-${isoDate.substring(0, 10)}.log`

  msg.map((line) => {
    logDebug(line)
    fs.appendFileSync(fileName, `[${isoDate}] ${line}\n`)
  })
}

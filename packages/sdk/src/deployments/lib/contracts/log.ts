import fs from 'fs'

import type { ContractReceipt, ContractTransaction } from 'ethers'
import type { ContractParam } from '../types/contract'
import { logInfo } from '../../logger'

export function logContractCall(
  tx: ContractTransaction,
  contractName: string,
  fn: string,
  args: Array<ContractParam>,
) {
  const msg: string[] = []
  msg.push(`> Sending transaction: ${contractName}.${fn}`)
  msg.push(`   = Sender: ${tx.from}`)
  msg.push(`   = Contract: ${tx.to}`)
  msg.push(`   = Params: [ ${args} ]`)
  msg.push(`   = TxHash: ${tx.hash}`)

  logToConsoleAndFile(msg)
}

export function logContractDeploy(
  tx: ContractTransaction,
  contractName: string,
  args: Array<ContractParam>,
) {
  const msg: string[] = []
  msg.push(`> Deploying contract: ${contractName}`)
  msg.push(`   = Sender: ${tx.from}`)
  msg.push(`   = Params: [ ${args} ]`)
  msg.push(`   = TxHash: ${tx.hash}`)
  logToConsoleAndFile(msg)
}

export function logContractDeployReceipt(
  receipt: ContractReceipt,
  creationCodeHash: string,
  runtimeCodeHash: string,
) {
  const msg: string[] = []
  msg.push(`   = CreationCodeHash: ${creationCodeHash}`)
  msg.push(`   = RuntimeCodeHash: ${runtimeCodeHash}`)
  logToConsoleAndFile(msg)
  logContractReceipt(receipt)
}

export function logContractReceipt(receipt: ContractReceipt) {
  const msg: string[] = []
  msg.push(receipt.status ? `   ✔ Transaction succeeded!` : `   ✖ Transaction failed!`)
  logToConsoleAndFile(msg)
}

export function logToConsoleAndFile(msg: string[]) {
  const isoDate = new Date().toISOString()
  const fileName = `tx-${isoDate.substring(0, 10)}.log`

  msg.map((line) => {
    logInfo(line)
    fs.appendFileSync(fileName, `[${isoDate}] ${line}\n`)
  })
}

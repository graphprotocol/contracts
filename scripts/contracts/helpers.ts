import * as fs from 'fs'
import * as path from 'path'
import * as dotenv from 'dotenv'

import { ContractTransaction, utils, ContractReceipt, providers, Wallet } from 'ethers'
import ipfsHttpClient from 'ipfs-http-client'
import * as bs58 from 'bs58'

dotenv.config()

// TODO - implement ganache mnenomic, from scripts/cli/constants
export const configureWallet = (wallet?: Wallet, network?: string): Wallet => {
  if (process.env.INFURA_KEY == undefined) {
    throw new Error(
      `Please create a .env file at the root of this project, and set INFURA_KEY=<YOUR_INFURA_KEY>`,
    )
  }
  if (network == undefined) {
    network = 'kovan'
  }
  const ethereum = `https://${network}.infura.io/v3/${process.env.INFURA_KEY}`
  const eth = new providers.JsonRpcProvider(ethereum)
  if (wallet == undefined) {
    try {
      wallet = Wallet.fromMnemonic(process.env.MNEMONIC)
    } catch {
      throw new Error(
        `Please create a .env file at the root of this project, and set MNEMONIC=<YOUR_12_WORD_MNEMONIC>`,
      )
    }
  }
  wallet = wallet.connect(eth)
  return wallet
}

// TODO - return address book type, not any
export const getNetworkAddresses = (network?: string): any => {
  let generatedAddresses
  let permanentAddresses
  const addresses = JSON.parse(
    fs.readFileSync(path.join(__dirname, '../..', 'addresses.json'), 'utf-8'),
  )
  if (network == undefined) {
    network = 'kovan'
    generatedAddresses = addresses['42']
    permanentAddresses = addresses.kovan // TODO - update address book so this doesn't happen
  }
  return {
    generatedAddresses: generatedAddresses,
    permanentAddresses: permanentAddresses,
  }
}

export const executeTransaction = async (
  transaction: Promise<ContractTransaction>,
): Promise<ContractReceipt> => {
  try {
    const tx = await transaction
    console.log(`  Transaction pending: 'https://kovan.etherscan.io/tx/${tx.hash}'`)
    const receipt = await tx.wait(1)
    console.log(`  Transaction successfully included in block #${receipt.blockNumber}`)
    return receipt
  } catch (e) {
    console.log(`  ..executeTransaction failed: ${e.message}`)
    process.exit(1)
  }
}

export const checkFuncInputs = (
  userInputs: Array<string | undefined>,
  inputNames: Array<string>,
  functionName: string,
): void => {
  userInputs.forEach((input, i) => {
    if (input == undefined) {
      console.error(`ERROR: ${inputNames[i]} was not provided for ${functionName}()`)
      process.exit(1)
    }
  })
}

export class IPFS {
  static createIpfsClient(node: string): ipfsHttpClient {
    let url: URL
    try {
      url = new URL(node)
    } catch (e) {
      throw new Error(
        `Invalid IPFS URL: ${node}. ` +
          `The URL must be of the following format: http(s)://host[:port]/[path]`,
      )
    }

    return ipfsHttpClient({
      protocol: url.protocol.replace(/[:]+$/, ''),
      host: url.hostname,
      port: url.port,
      'api-path': url.pathname.replace(/\/$/, '') + '/api/v0/',
    })
  }

  static ipfsHashToBytes32(hash: string): string {
    const hashBytes = bs58.decode(hash).slice(2)
    console.log(`base58 to bytes32: ${hash} -> ${utils.hexlify(hashBytes)}`)
    return utils.hexlify(hashBytes)
  }
}

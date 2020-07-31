import * as fs from 'fs'
import * as path from 'path'
import * as dotenv from 'dotenv'

import { ContractTransaction, utils, ContractReceipt, providers, Wallet, Overrides } from 'ethers'
import ipfsHttpClient from 'ipfs-http-client'
import * as bs58 from 'bs58'

dotenv.config()

export const DEFAULT_MNEMONIC =
  'myth like bonus scare over problem client lizard pioneer submit female collect'
export const GANACHE_ENDPOINT = 'http://localhost:8545'

export const buildNetworkEndpoint = (
  network: string,
  provider?: string,
  providerAPIKey?: string,
): string => {
  if (network == 'ganache') return GANACHE_ENDPOINT
  if (provider == 'infura') {
    if (providerAPIKey == undefined) {
      if (process.env.INFURA_KEY == undefined) {
        throw new Error(
          `Please create a .env file at the root of this project, and set INFURA_KEY=<YOUR_INFURA_KEY>, or pass in an API key`,
        )
      } else {
        return `https://${network}.infura.io/v3/${process.env.INFURA_KEY}`
      }
    } else {
      return `https://${network}.infura.io/v3/${providerAPIKey}`
    }
  } else {
    throw new Error(`Only infura or local with ganache works for provider endpoint`)
  }
}

// Creates an array of wallets connected to a provider
export const configureWallets = (
  mnemonic: string,
  providerEndpoint: string,
  count: number,
): Array<Wallet> => {
  const signers: Array<Wallet> = []
  for (let i = 0; i < count; i++) {
    signers.push(configureWallet(mnemonic, providerEndpoint, i.toString()))
  }
  console.log(`Created ${count} wallets!`)
  return signers
}

export const configureGanacheWallet = (): Wallet => {
  return configureWallet(DEFAULT_MNEMONIC, GANACHE_ENDPOINT)
}

// Create a single wallet connected to a provider
export const configureWallet = (
  mnemonic: string,
  providerEndpoint: string,
  index = '0',
): Wallet => {
  if (mnemonic == undefined) {
    throw new Error(`Please set a mnemonic in a .env file at the root of the project`)
  }
  const wallet = Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${index}`)
  const eth = new providers.JsonRpcProvider(providerEndpoint)
  return wallet.connect(eth)
}

// Check governor for the network
export const checkGovernor = (address: string, network: string): void => {
  const networkAddresses = getNetworkAddresses(network)
  const governor = networkAddresses.generatedAddresses.GraphToken.constructorArgs[0].value
  console.log(governor)
  if (address == governor) {
    return
  } else {
    throw new Error('You are trying to call a governor function from the wrong account')
  }
}

// TODO - return address book type, not any
export const getNetworkAddresses = (network: string): any => {
  let generatedAddresses
  let permanentAddresses
  const addresses = JSON.parse(
    fs.readFileSync(path.join(__dirname, '../..', 'addresses.json'), 'utf-8'),
  )
  if (network == 'kovan') {
    generatedAddresses = addresses['42']
    permanentAddresses = addresses.kovan // TODO - update address book so this doesn't happen
  } else if (network == 'rinkeby') {
    generatedAddresses = addresses['4']
    permanentAddresses = addresses.rinkeby
  } else if (network == 'ganache') {
    generatedAddresses = addresses['1337']
    // TODO - make this connect to ENS and etherDIDRegistry when it is working
    permanentAddresses = addresses.kovan
  }
  return {
    generatedAddresses,
    permanentAddresses,
  }
}

export const basicOverrides = (): Overrides => {
  return {
    gasPrice: utils.parseUnits('25', 'gwei'),
    gasLimit: 2000000,
  }
}

export const executeTransaction = async (
  transaction: Promise<ContractTransaction>,
  network: string,
): Promise<ContractReceipt> => {
  try {
    const tx = await transaction
    console.log(`  Transaction pending: 'https://${network}.etherscan.io/tx/${tx.hash}'`)
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
    return utils.hexlify(hashBytes)
  }
}
export const mockDeploymentIDsBase58: Array<string> = [
  'Qmb7e8bYoj93F9u33R3JY1H764626C8KHUgWMeVjWPiwdD', //compound
  'QmXenxBqM7uBbRq6y7EAcy86mfcaBkWE53Tz53H3dVeeit', //used synthetix
  'QmY8Uzg61ttrogeTyCKLcDDR4gKNK44g9qkGDqeProkSHE', //ens
  'QmRkqEVeZ8bRmMfvBHJvoB4NbnPgXNcuszLZWNNF49skY8', //livepeer
  'Qmb3hd2hYd2nWFgcmRswykF1dUBSrDUrinYCgN1dmE1tNy', //maker
  'QmcqrL62BHSasBsk47tNT1G66BHbaANwY213cX841NWE61', //melon
  'QmTXzATwNfgGVukV1fX2T6xw9f6LAYRVWpsdXyRWzUR2H9', // moloch
  'QmNoMRb9c5nGi5gETeyeAc7V14XvubAMAA7sxEJzsXnpTF', //used aave
  'QmUVKS3W7G7Kog6pGq2ttZtXfE89pRvw45vEJM2YEYwpQz', //thegraph
  'QmNPKaPqgTqKdCv2k3SF9vAhbHo4PVb2cKx2Gs4PzNQkZx', //uniswap
]

export const mockDeploymentIDsBytes32: Array<string> = [
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[1]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
  IPFS.ipfsHashToBytes32(mockDeploymentIDsBase58[0]),
]

export const mockChannelPubKeys: Array<string> = [
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d50',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d51',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d52',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d54',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d55',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d56',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d57',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d58',
  '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d59',
]

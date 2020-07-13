import { providers, utils, Contract, ContractFactory, ContractTransaction, Wallet } from 'ethers'
import consola from 'consola'

import { AddressBook } from './address-book'
import { loadArtifact } from './artifacts'
import { promisify } from 'util'
import { pseudoRandomBytes } from 'crypto'

const { keccak256 } = utils

const logger = consola.create({})

const hash = (input: string): string => keccak256(`0x${input.replace(/^0x/, '')}`)

// Simple sanity checks to make sure contracts from our address book have been deployed
export const isContractDeployed = async (
  name: string,
  address: string | undefined,
  addressBook: AddressBook,
  provider: providers.Provider,
): Promise<boolean> => {
  logger.log(`Checking for valid ${name} contract...`)
  if (!address || address === '') {
    logger.warn('This contract is not in our address book.')
    return false
  }

  const addressEntry = addressBook.getEntry(name)

  const savedCreationCodeHash = addressEntry.creationCodeHash
  const creationCodeHash = hash(loadArtifact(name).bytecode)
  if (!savedCreationCodeHash || savedCreationCodeHash !== creationCodeHash) {
    logger.warn(`creationCodeHash in our address book doen't match ${name} artifacts`)
    logger.log(`${savedCreationCodeHash} !== ${creationCodeHash}`)
    return false
  }

  const savedRuntimeCodeHash = addressEntry.runtimeCodeHash
  const runtimeCodeHash = hash(await provider.getCode(address))
  if (runtimeCodeHash === hash('0x00') || runtimeCodeHash === hash('0x')) {
    logger.warn('No runtimeCode exists at the address in our address book')
    return false
  }
  if (savedRuntimeCodeHash !== runtimeCodeHash) {
    logger.warn(`runtimeCodeHash for ${address} does not match what's in our address book`)
    logger.log(`${savedRuntimeCodeHash} !== ${runtimeCodeHash}`)
    return false
  }
  return true
}

export const sendTransaction = async (
  wallet: Wallet,
  contract: Contract,
  fn: string,
  ...params
): Promise<providers.TransactionReceipt> => {
  const tx: ContractTransaction = await contract.functions[fn](...params)
  logger.log(`> Sent transaction ${fn}: ${params}, txHash: ${tx.hash}`)
  const receipt = await wallet.provider.waitForTransaction(tx.hash)
  logger.success(`Transaction mined ${tx.hash}`)
  return receipt
}

export const deployProxy = async (wallet: Wallet): Promise<Contract> => {
  const artifact = loadArtifact('GraphProxy')
  const factory = ContractFactory.fromSolidity(artifact)
  const contract = await factory.connect(wallet).deploy()
  const txHash = contract.deployTransaction.hash
  logger.log(`> Sent transaction to deploy Proxy, txHash: ${txHash}`)
  await wallet.provider.waitForTransaction(txHash)
  const address = contract.address
  logger.success(`Proxy has been deployed to address: ${address}`)
  return contract
}

export const deployContractWithProxy = async (
  name: string,
  args: Array<{ name: string; value: string }>,
  wallet: Wallet,
  addressBook: AddressBook,
): Promise<Contract> => {
  // Deploy proxy
  const proxy = await deployProxy(wallet)
  // Deploy implementation
  const contract = await deployContract(name, [], wallet, addressBook)
  // Upgrade to implementation
  await sendTransaction(wallet, proxy, 'upgradeTo', contract.address)
  // Implementation accepts upgrade
  await sendTransaction(
    wallet,
    contract,
    'acceptUpgrade',
    ...[proxy.address, ...args.map((a) => a.value)],
  )

  // Overwrite address book entry with proxy
  const artifact = loadArtifact('GraphToken')
  const contractEntry = addressBook.getEntry(name)
  addressBook.setEntry(name, {
    address: proxy.address,
    initArgs: args.length === 0 ? undefined : args,
    creationCodeHash: hash(artifact.bytecode),
    runtimeCodeHash: hash(await wallet.provider.getCode(proxy.address)),
    txHash: proxy.deployTransaction.hash,
    proxy: true,
    implementation: contractEntry,
  })

  // Use interface of contract but with the proxy address
  return contract.attach(proxy.address)
}

export const deployContract = async (
  name: string,
  args: Array<{ name: string; value: string }>,
  wallet: Wallet,
  addressBook: AddressBook,
): Promise<Contract> => {
  const artifact = loadArtifact(name)
  const factory = ContractFactory.fromSolidity(artifact)
  const contract = await factory.connect(wallet).deploy(...args.map((a) => a.value))
  const txHash = contract.deployTransaction.hash
  logger.log(`> Sent transaction to deploy ${name}, txHash: ${txHash}`)
  await wallet.provider.waitForTransaction(txHash)
  const address = contract.address
  logger.success(`${name} has been deployed to address: ${address}`)
  const runtimeCodeHash = hash(await wallet.provider.getCode(address))
  const creationCodeHash = hash(artifact.bytecode)
  addressBook.setEntry(name, {
    address,
    constructorArgs: args.length === 0 ? undefined : args,
    creationCodeHash,
    runtimeCodeHash,
    txHash,
  })

  return contract
}

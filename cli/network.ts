import { providers, utils, Contract, ContractFactory, ContractTransaction, Wallet } from 'ethers'
import consola from 'consola'

import { AddressBook } from './address-book'
import { loadArtifact } from './artifacts'
import { defaultOverrides } from './helpers'

const { keccak256 } = utils

const logger = consola.create({})

const hash = (input: string): string => keccak256(`0x${input.replace(/^0x/, '')}`)

// Simple sanity checks to make sure contracts from our address book have been deployed
export const isContractDeployed = async (
  name: string,
  address: string | undefined,
  addressBook: AddressBook,
  provider: providers.Provider,
  checkCreationCode = true,
): Promise<boolean> => {
  logger.log(`Checking for valid ${name} contract...`)
  if (!address || address === '') {
    logger.warn('This contract is not in our address book.')
    return false
  }

  const addressEntry = addressBook.getEntry(name)

  // If the contract is behind a proxy we check the Proxy artifact instead
  const artifact = addressEntry.proxy === true ? loadArtifact('GraphProxy') : loadArtifact(name)

  if (checkCreationCode) {
    const savedCreationCodeHash = addressEntry.creationCodeHash
    const creationCodeHash = hash(artifact.bytecode)
    if (!savedCreationCodeHash || savedCreationCodeHash !== creationCodeHash) {
      logger.warn(`creationCodeHash in our address book doesn't match ${name} artifacts`)
      logger.log(`${savedCreationCodeHash} !== ${creationCodeHash}`)
      return false
    }
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
  let tx: ContractTransaction
  try {
    console.log()
    tx = await contract.functions[fn](...params)
    if (tx == undefined) {
      logger.error(`It appears the function does not exist on this contract`)
    }
  } catch (e) {
    if (e.code == 'UNPREDICTABLE_GAS_LIMIT') {
      logger.warn(`Gas could not be estimated - trying defaultOverrides`)
      tx = await contract.functions[fn](...params, defaultOverrides())
    } else {
      logger.error(e)
    }
  }
  logger.log(`> Sent transaction ${fn}: ${params}, txHash: ${tx.hash}`)
  const receipt = await wallet.provider.waitForTransaction(tx.hash)
  const networkName = (await wallet.provider.getNetwork()).name
  if (networkName == 'kovan' || networkName == 'rinkeby') {
    logger.success(`Transaction mined 'https://${networkName}.etherscan.io/tx/${tx.hash}'`)
  } else {
    logger.success(`Transaction mined ${tx.hash}`)
  }
  return receipt
}

export const getContractFactory = (name: string): ContractFactory => {
  const artifact = loadArtifact(name)
  return ContractFactory.fromSolidity(artifact)
}

export const getContractAt = (name: string, address: string): Contract => {
  return getContractFactory(name).attach(address)
}

export const deployContract = async (
  name: string,
  args: Array<string>,
  wallet: Wallet,
): Promise<Contract> => {
  const factory = getContractFactory(name)

  const contract = await factory.connect(wallet).deploy(...args)
  const txHash = contract.deployTransaction.hash
  logger.log(`> Deploy ${name}, txHash: ${txHash}`)
  await wallet.provider.waitForTransaction(txHash)

  logger.log('= CreationCodeHash: ', hash(factory.bytecode))
  logger.log('= RuntimeCodeHash: ', hash(await wallet.provider.getCode(contract.address)))
  logger.success(`${name} has been deployed to address: ${contract.address}`)

  return contract
}

export const deployContractAndSave = async (
  name: string,
  args: Array<{ name: string; value: string }>,
  wallet: Wallet,
  addressBook: AddressBook,
): Promise<Contract> => {
  // Deploy the contract
  const contract = await deployContract(
    name,
    args.map((a) => a.value),
    wallet,
  )

  // Save address entry
  const artifact = loadArtifact(name)
  addressBook.setEntry(name, {
    address: contract.address,
    constructorArgs: args.length === 0 ? undefined : args,
    creationCodeHash: hash(artifact.bytecode),
    runtimeCodeHash: hash(await wallet.provider.getCode(contract.address)),
    txHash: contract.deployTransaction.hash,
  })

  return contract
}

export const deployContractWithProxyAndSave = async (
  name: string,
  args: Array<{ name: string; value: string }>,
  wallet: Wallet,
  addressBook: AddressBook,
): Promise<Contract> => {
  // Deploy implementation
  const contract = await deployContractAndSave(name, [], wallet, addressBook)
  // Deploy proxy
  const proxy = await deployContract('GraphProxy', [contract.address], wallet)
  // Implementation accepts upgrade
  await sendTransaction(
    wallet,
    contract,
    'acceptProxy',
    ...[proxy.address, ...args.map((a) => a.value)],
  )

  // Overwrite address entry with proxy
  const artifact = loadArtifact('GraphProxy')
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

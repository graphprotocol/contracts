import { LinkReferences } from '@nomiclabs/buidler/types'

import { providers, utils, Contract, ContractFactory, ContractTransaction, Signer } from 'ethers'
import consola from 'consola'

import { AddressBook } from './address-book'
import { loadArtifact } from './artifacts'
import { defaultOverrides } from './helpers'

const { keccak256 } = utils

const logger = consola.create({})

const hash = (input: string): string => keccak256(`0x${input.replace(/^0x/, '')}`)

type DeployResult = {
  contract: Contract
  creationCodeHash: string
  runtimeCodeHash: string
  txHash: string
  libraries?: { [libraryName: string]: string }
}

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
  sender: Signer,
  contract: Contract,
  fn: string,
  ...params
): Promise<providers.TransactionReceipt> => {
  // Send transaction
  let tx: ContractTransaction
  try {
    tx = await contract.functions[fn](...params)
  } catch (e) {
    if (e.code == 'UNPREDICTABLE_GAS_LIMIT') {
      logger.warn(`Gas could not be estimated - trying defaultOverrides`)
      tx = await contract.functions[fn](...params, defaultOverrides())
    } else {
      throw e
    }
  }
  if (tx == undefined) {
    logger.error(
      `It appears the function does not exist on this contract, or you have the wrong contract address`,
    )
  }
  logger.log(`> Sent transaction ${fn}: ${params}, txHash: ${tx.hash}`)
  // Wait for transaction to be mined
  const receipt = await sender.provider.waitForTransaction(tx.hash)
  const networkName = (await sender.provider.getNetwork()).name
  if (networkName === 'kovan' || networkName === 'rinkeby') {
    logger.success(`Transaction mined 'https://${networkName}.etherscan.io/tx/${tx.hash}'`)
  } else {
    logger.success(`Transaction mined ${tx.hash}`)
  }
  return receipt
}

export const getContractFactory = (
  name: string,
  libraries?: { [libraryName: string]: string },
): ContractFactory => {
  const artifact = loadArtifact(name)
  // Fixup libraries
  if (libraries && Object.keys(libraries).length > 0) {
    artifact.bytecode = linkLibraries(artifact, libraries)
  }
  return new ContractFactory(artifact.abi, artifact.bytecode)
}

export const getContractAt = (name: string, address: string): Contract => {
  const artifact = loadArtifact(name)
  return new Contract(address, artifact.abi)
}

export const deployContract = async (
  name: string,
  args: Array<string>,
  sender: Signer,
  autolink = true,
  silent = false,
): Promise<DeployResult> => {
  // This function will autolink, that means it will automatically deploy external libraries
  // and link them to the contract
  const libraries = {}
  if (autolink) {
    const artifact = loadArtifact(name)
    if (artifact.linkReferences && Object.keys(artifact.linkReferences).length > 0) {
      for (const fileReferences of Object.values(artifact.linkReferences)) {
        for (const libName of Object.keys(fileReferences)) {
          const deployResult = await deployContract(libName, [], sender, false, silent)
          libraries[libName] = deployResult.contract.address
        }
      }
    }
  }

  // Deploy
  const factory = getContractFactory(name, libraries)
  const contract = await factory.connect(sender).deploy(...args)
  const txHash = contract.deployTransaction.hash
  if (!silent) {
    logger.log(`> Deploy ${name}, txHash: ${txHash}`)
  }
  await sender.provider.waitForTransaction(txHash)

  // Receipt
  const creationCodeHash = hash(factory.bytecode)
  const runtimeCodeHash = hash(await sender.provider.getCode(contract.address))
  if (!silent) {
    logger.log('= CreationCodeHash: ', creationCodeHash)
    logger.log('= RuntimeCodeHash: ', runtimeCodeHash)
    logger.success(`${name} has been deployed to address: ${contract.address}`)
  }

  return { contract, creationCodeHash, runtimeCodeHash, txHash, libraries }
}

export const deployContractAndSave = async (
  name: string,
  args: Array<{ name: string; value: string }>,
  sender: Signer,
  addressBook: AddressBook,
): Promise<Contract> => {
  // Deploy the contract
  const deployResult = await deployContract(
    name,
    args.map((a) => a.value),
    sender,
  )

  // Save address entry
  addressBook.setEntry(name, {
    address: deployResult.contract.address,
    constructorArgs: args.length === 0 ? undefined : args,
    creationCodeHash: deployResult.creationCodeHash,
    runtimeCodeHash: deployResult.runtimeCodeHash,
    txHash: deployResult.txHash,
    libraries:
      deployResult.libraries && Object.keys(deployResult.libraries).length > 0
        ? deployResult.libraries
        : undefined,
  })

  return deployResult.contract
}

export const deployContractWithProxyAndSave = async (
  name: string,
  args: Array<{ name: string; value: string }>,
  sender: Signer,
  addressBook: AddressBook,
): Promise<Contract> => {
  // Deploy implementation
  const contract = await deployContractAndSave(name, [], sender, addressBook)
  // Deploy proxy
  const deployResult = await deployContract('GraphProxy', [contract.address], sender)
  const proxy = deployResult.contract
  // Implementation accepts upgrade
  await sendTransaction(
    sender,
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
    runtimeCodeHash: hash(await sender.provider.getCode(proxy.address)),
    txHash: proxy.deployTransaction.hash,
    proxy: true,
    implementation: contractEntry,
  })

  // Use interface of contract but with the proxy address
  return contract.attach(proxy.address)
}

export const linkLibraries = (
  artifact: {
    bytecode: string
    linkReferences?: LinkReferences
  },
  libraries?: { [libraryName: string]: string },
): string => {
  let bytecode = artifact.bytecode

  if (libraries) {
    if (artifact.linkReferences) {
      for (const [fileName, fileReferences] of Object.entries(artifact.linkReferences)) {
        for (const [libName, fixups] of Object.entries(fileReferences)) {
          const addr = libraries[libName]
          if (addr === undefined) {
            continue
          }

          for (const fixup of fixups) {
            bytecode =
              bytecode.substr(0, 2 + fixup.start * 2) +
              addr.substr(2) +
              bytecode.substr(2 + (fixup.start + fixup.length) * 2)
          }
        }
      }
    }
  }
  return bytecode
}

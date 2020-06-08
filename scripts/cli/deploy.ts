import { Contract, ContractFactory, Wallet, providers, utils } from 'ethers'

import { AddressBook } from './address-book'
import { loadArtifact } from './artifacts'

const { keccak256 } = utils

const hash = (input: string): string => keccak256(`0x${input.replace(/^0x/, '')}`)

// Simple sanity checks to make sure contracts from our address book have been deployed
export const isContractDeployed = async (
  name: string,
  address: string | undefined,
  addressBook: AddressBook,
  provider: providers.Provider,
): Promise<boolean> => {
  console.log(`Checking for valid ${name} contract...`)
  if (!address || address === '') {
    console.log('This contract is not in our address book.')
    return false
  }
  const savedCreationCodeHash = addressBook.getEntry(name).creationCodeHash
  const creationCodeHash = hash(loadArtifact(name).bytecode)
  if (!savedCreationCodeHash || savedCreationCodeHash !== creationCodeHash) {
    console.log(`creationCodeHash in our address book doen't match ${name} artifacts`)
    console.log(`${savedCreationCodeHash} !== ${creationCodeHash}`)
    return false
  }
  const savedRuntimeCodeHash = addressBook.getEntry(name).runtimeCodeHash
  const runtimeCodeHash = hash(await provider.getCode(address))
  if (runtimeCodeHash === hash('0x00') || runtimeCodeHash === hash('0x')) {
    console.log('No runtimeCode exists at the address in our address book')
    return false
  }
  if (savedRuntimeCodeHash !== runtimeCodeHash) {
    console.log(`runtimeCodeHash for ${address} does not match what's in our address book`)
    console.log(`${savedRuntimeCodeHash} !== ${runtimeCodeHash}`)
    return false
  }
  return true
}

export const deployContract = async (
  name: string,
  args: Array<{ name: string; value: string }>,
  wallet: Wallet,
  addressBook: AddressBook,
): Promise<Contract> => {
  const artifact = loadArtifact(name)
  const factory = ContractFactory.fromSolidity(artifact)
  const contract = await factory.connect(wallet).deploy(...args.map(a => a.value))
  const txHash = contract.deployTransaction.hash
  console.log(`Sent transaction to deploy ${name}, txHash: ${txHash}`)
  await wallet.provider.waitForTransaction(txHash!)
  const address = contract.address
  console.log(`${name} has been deployed to address: ${address}\n`)
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

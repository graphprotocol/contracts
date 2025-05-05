import { deployContract, deployContractAndSave } from './contract'
import { DeployType, isDeployType } from '../types/deploy'
import { providers } from 'ethers'

import type { Signer } from 'ethers'
import type { DeployData, DeployResult } from '../types/deploy'
import type { AddressBook } from '../address-book'
import { loadArtifact } from './artifacts'
import { hashHexString } from '../../../utils/hash'
import { assertObject } from '../../../utils/assertions'

/**
 * Checks wether a contract is deployed or not
 *
 * @param name Name of the contract to check
 * @param proxyName Name of the contract proxy if there is one
 * @param address Address of the contract
 * @param addressBook Address book to use
 * @param provider Provider to use
 * @param checkCreationCode Check the creation code of the contract. Defaults to `true`
 * @returns `true` if the contract is deployed, `false` otherwise.
 */
export const isContractDeployed = async (
  name: string,
  proxyName: string,
  address: string | undefined,
  addressBook: AddressBook,
  provider: providers.Provider,
  checkCreationCode = true,
): Promise<boolean> => {
  console.info(`Checking for valid ${name} contract...`)
  if (!address || address === '') {
    console.warn('This contract is not in our address book.')
    return false
  }

  const addressEntry = addressBook.getEntry(name)

  // If the contract is behind a proxy we check the Proxy artifact instead
  const artifact = addressEntry.proxy === true ? loadArtifact(proxyName) : loadArtifact(name)

  if (checkCreationCode) {
    const savedCreationCodeHash = addressEntry.creationCodeHash
    const creationCodeHash = hashHexString(artifact.bytecode)
    if (!savedCreationCodeHash || savedCreationCodeHash !== creationCodeHash) {
      console.warn(`creationCodeHash in our address book doesn't match ${name} artifacts`)
      console.info(`${savedCreationCodeHash} !== ${creationCodeHash}`)
      return false
    }
  }

  const savedRuntimeCodeHash = addressEntry.runtimeCodeHash
  const runtimeCodeHash = hashHexString(await provider.getCode(address))
  if (runtimeCodeHash === hashHexString('0x00') || runtimeCodeHash === hashHexString('0x')) {
    console.warn('No runtimeCode exists at the address in our address book')
    return false
  }
  if (savedRuntimeCodeHash !== runtimeCodeHash) {
    console.warn(`runtimeCodeHash for ${address} does not match what's in our address book`)
    console.info(`${savedRuntimeCodeHash} !== ${runtimeCodeHash}`)
    return false
  }
  return true
}

export const deploy = async (
  type: DeployType | unknown,
  sender: Signer,
  contractData: DeployData,
  addressBook?: AddressBook,
  _proxyData?: DeployData,
): Promise<DeployResult> => {
  if (!isDeployType(type)) {
    throw new Error('Please provide the correct option for deploy type')
  }

  switch (type) {
    case DeployType.Deploy:
      console.info(`Deploying contract ${contractData.name}...`)
      return await deployContract(sender, contractData)
    case DeployType.DeployAndSave:
      console.info(`Deploying contract ${contractData.name} and saving to address book...`)
      assertObject(addressBook)
      return await deployContractAndSave(sender, contractData, addressBook)
    case DeployType.DeployWithProxy:
    case DeployType.DeployWithProxyAndSave:
    case DeployType.DeployImplementationAndSave:
      throw new Error(`Base SDK does not implement ${type} deployments.`)
    default:
      throw new Error('Please provide the correct option for deploy type')
  }
}

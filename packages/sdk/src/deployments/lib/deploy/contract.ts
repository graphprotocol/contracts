import { loadArtifact } from './artifacts'
import { getContractFactory } from './factory'
import { AddressBook } from '../address-book'
import { hashHexString } from '../../../utils/hash'
import { logInfo } from '../../logger'
import type { Signer } from 'ethers'
import type {
  DeployData,
  DeployResult,
  DeployFunction,
  DeployAddressBookFunction,
} from '../types/deploy'
import { logContractDeploy, logContractDeployReceipt } from '../contracts/log'

/**
 * Deploys a contract
 *
 * @remarks This function will autolink, that means it will automatically deploy external libraries
 * and link them to the contract if needed
 *
 * @param sender Signer to deploy the contract with, must be already connected to a provider
 * @param name Name of the contract to deploy
 * @param args Contract constructor arguments
 * @param autolink Wether or not to autolink. Defaults to true.
 * @returns the deployed contract and deployment metadata associated to it
 *
 * @throws Error if the sender is not connected to a provider
 */
export const deployContract: DeployFunction = async (
  sender: Signer,
  contractData: DeployData,
): Promise<DeployResult> => {
  const name = contractData.name
  const args = contractData.args ?? []
  const opts = contractData.opts ?? {}

  if (!sender.provider) {
    throw Error('Sender must be connected to a provider')
  }

  // Autolink
  const libraries = {} as Record<string, string>
  if (opts?.autolink ?? true) {
    const artifact = loadArtifact(name)
    if (artifact.linkReferences && Object.keys(artifact.linkReferences).length > 0) {
      for (const fileReferences of Object.values(artifact.linkReferences)) {
        for (const libName of Object.keys(fileReferences)) {
          const deployResult = await deployContract(sender, {
            name: libName,
            args: [],
            opts: { autolink: false },
          })
          libraries[libName] = deployResult.contract.address
        }
      }
    }
  }

  // Deploy
  const factory = getContractFactory(name, libraries)
  const contract = await factory.connect(sender).deploy(...args)
  const txHash = contract.deployTransaction.hash
  logContractDeploy(contract.deployTransaction, name, args)
  const receipt = await sender.provider.waitForTransaction(txHash)

  // Receipt
  const creationCodeHash = hashHexString(factory.bytecode)
  const runtimeCodeHash = hashHexString(await sender.provider.getCode(contract.address))
  logContractDeployReceipt(receipt, creationCodeHash, runtimeCodeHash)

  return { contract, creationCodeHash, runtimeCodeHash, txHash, libraries }
}

/**
 * Deploys a contract and saves the deployment result to the address book
 *
 * @remarks Same as {@link deployContract} but this variant will also save the deployment result to the address book.
 *
 * @param sender Signer to deploy the contract with, must be already connected to a provider
 * @param name Name of the contract to deploy
 * @param args Contract constructor arguments
 * @param addressBook Address book to save the deployment result to
 * @returns the deployed contract and deployment metadata associated to it
 *
 * @throws Error if the sender is not connected to a provider
 */
export const deployContractAndSave: DeployAddressBookFunction = async (
  sender: Signer,
  contractData: DeployData,
  addressBook: AddressBook,
): Promise<DeployResult> => {
  const name = contractData.name
  const args = contractData.args ?? []

  if (!sender.provider) {
    throw Error('Sender must be connected to a provider')
  }

  // Deploy the contract
  const deployResult = await deployContract(sender, {
    name: name,
    args: args,
  })

  const constructorArgs = args.map((e) => {
    if (Array.isArray(e)) {
      return e.map((e) => e.toString())
    } else {
      return e.toString()
    }
  })

  // Save address entry
  addressBook.setEntry(name, {
    address: deployResult.contract.address,
    constructorArgs: constructorArgs,
    creationCodeHash: deployResult.creationCodeHash,
    runtimeCodeHash: deployResult.runtimeCodeHash,
    txHash: deployResult.txHash,
    libraries:
      deployResult.libraries && Object.keys(deployResult.libraries).length > 0
        ? deployResult.libraries
        : undefined,
  })
  logInfo('> Contract saved to address book')

  return deployResult
}

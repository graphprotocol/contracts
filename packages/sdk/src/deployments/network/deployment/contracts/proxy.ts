import { loadArtifact } from '../../../lib/deploy/artifacts'
import { AddressBook } from '../../../lib/address-book'
import { deployContract, deployContractAndSave } from '../../../lib/deploy/contract'
import { hashHexString } from '../../../../utils/hash'
import { loadContractAt } from '../../../lib/contracts/load'
import { getArtifactsPath } from './load'

import type { Contract, Signer } from 'ethers'
import type { ContractParam } from '../../../lib/types/contract'
import type {
  DeployAddressBookWithProxyFunction,
  DeployData,
  DeployResult,
} from '../../../lib/types/deploy'
import { logDebug } from '../../../logger'

/**
 * Deploys a contract with a proxy
 *
 * @remarks Sets a contract as the proxy admin
 * @remarks The proxy admin needs to
 * @remarks This function can deploy any proxy contract as long as the constructor has the following signature:
 * `constructor(address implementation, address admin)`
 *
 * @param sender Signer to deploy the contract with, must be already connected to a provider
 * @param name Name of the contract to deploy
 * @param args Contract constructor arguments
 * @param proxyName Name of the proxy contract to deploy
 * @param proxyAdmin Contract to be used as the proxy admin
 * @param buildAcceptTx If set to true it will build the accept tx and print it to the console. Defaults to `false`
 * @returns the deployed contract with the proxy address
 *
 * @throws Error if the sender is not connected to a provider
 */
export const deployContractWithProxy: DeployAddressBookWithProxyFunction = async (
  sender: Signer,
  contractData: DeployData,
  addressBook: AddressBook,
  proxyData: DeployData,
): Promise<DeployResult> => {
  if (!sender.provider) {
    throw Error('Sender must be connected to a provider')
  }

  const proxyAdmin = getProxyAdmin(addressBook)

  // Deploy implementation
  const implDeployResult = await deployContract(sender, {
    name: contractData.name,
    args: [],
  })

  // Deploy proxy
  const { contract: proxy } = await deployContract(sender, {
    name: proxyData.name,
    args: [implDeployResult.contract.address, proxyAdmin.address],
    opts: { autolink: false },
  })

  // Accept implementation upgrade
  await proxyAdminAcceptUpgrade(
    sender,
    implDeployResult.contract,
    contractData.args ?? [],
    proxyAdmin,
    proxy.address,
    proxyData.opts?.buildAcceptTx ?? false,
  )

  // Use interface of contract but with the proxy address
  implDeployResult.contract = implDeployResult.contract.attach(proxy.address)
  return implDeployResult
}

/**
 * Deploys a contract with a proxy and saves the deployment result to the address book
 *
 * @remarks Same as {@link deployContractWithProxy} but this variant will also save the deployment result to the address book.
 *
 * @param proxyName Name of the proxy contract to deploy
 * @param proxyAdmin Proxy admin contract
 * @param name Name of the contract to deploy
 * @param args Contract constructor arguments
 * @param sender Signer to deploy the contract with, must be already connected to a provider
 * @param buildAcceptTx If set to true it will build the accept tx and print it to the console. Defaults to `false`
 * @returns the deployed contract with the proxy address
 *
 * @throws Error if the sender is not connected to a provider
 */
export const deployContractWithProxyAndSave: DeployAddressBookWithProxyFunction = async (
  sender: Signer,
  contractData: DeployData,
  addressBook: AddressBook,
  proxyData: DeployData,
): Promise<DeployResult> => {
  if (!sender.provider) {
    throw Error('Sender must be connected to a provider')
  }

  const proxyAdmin = getProxyAdmin(addressBook)

  // Deploy implementation
  const implDeployResult = await deployContractAndSave(
    sender,
    {
      name: contractData.name,
      args: [],
    },
    addressBook,
  )

  // Deploy proxy
  const { contract: proxy } = await deployContract(sender, {
    name: proxyData.name,
    args: [implDeployResult.contract.address, proxyAdmin.address],
    opts: { autolink: false },
  })

  // Accept implementation upgrade
  await proxyAdminAcceptUpgrade(
    sender,
    implDeployResult.contract,
    contractData.args ?? [],
    proxyAdmin,
    proxy.address,
    proxyData.opts?.buildAcceptTx ?? false,
  )

  // Overwrite address entry with proxy
  const artifact = loadArtifact(proxyData.name)
  const contractEntry = addressBook.getEntry(contractData.name)

  addressBook.setEntry(contractData.name, {
    address: proxy.address,
    initArgs:
      contractData.args?.length === 0 ? undefined : contractData.args?.map((e) => e.toString()),
    creationCodeHash: hashHexString(artifact.bytecode),
    runtimeCodeHash: hashHexString(await sender.provider.getCode(proxy.address)),
    txHash: proxy.deployTransaction.hash,
    proxy: true,
    implementation: contractEntry,
  })
  logDebug('> Contract saved to address book')

  // Use interface of contract but with the proxy address
  implDeployResult.contract = implDeployResult.contract.attach(proxy.address)
  return implDeployResult
}

export const deployContractImplementationAndSave: DeployAddressBookWithProxyFunction = async (
  sender: Signer,
  contractData: DeployData,
  addressBook: AddressBook,
  proxyData: DeployData,
): Promise<DeployResult> => {
  if (!sender.provider) {
    throw Error('Sender must be connected to a provider')
  }

  const proxyAdmin = getProxyAdmin(addressBook)

  // Deploy implementation
  const implDeployResult = await deployContract(sender, {
    name: contractData.name,
    args: [],
  })

  // Get proxy entry
  const contractEntry = addressBook.getEntry(contractData.name)

  // Accept implementation upgrade
  await proxyAdminAcceptUpgrade(
    sender,
    implDeployResult.contract,
    contractData.args ?? [],
    proxyAdmin,
    contractEntry.address,
    proxyData.opts?.buildAcceptTx ?? false,
  )

  // Save address entry
  contractEntry.implementation = {
    address: implDeployResult.contract.address,
    constructorArgs:
      contractData.args?.length === 0 ? undefined : contractData.args?.map((e) => e.toString()),
    creationCodeHash: implDeployResult.creationCodeHash,
    runtimeCodeHash: implDeployResult.runtimeCodeHash,
    txHash: implDeployResult.txHash,
    libraries:
      implDeployResult.libraries && Object.keys(implDeployResult.libraries).length > 0
        ? implDeployResult.libraries
        : undefined,
  }
  addressBook.setEntry(contractData.name, contractEntry)
  logDebug('> Contract saved to address book')

  // Use interface of contract but with the proxy address
  implDeployResult.contract = implDeployResult.contract.attach(contractEntry.address)
  return implDeployResult
}

/**
 * Accepts an upgrade for a proxy contract managed by a proxy admin
 *
 * @remarks Initializes the implementation if init arguments are provided
 *
 * @privateRemarks This function is highly specific to the graph protocol proxy system
 *
 * @param sender Signer to make the call to the proxy admin contract
 * @param contract Implementation contract
 * @param args Implementation initialization arguments
 * @param proxyAdmin Proxy admin contract
 * @param buildAcceptTx If set to true it will build the accept tx and print it to the console. Defaults to `false`
 */
const proxyAdminAcceptUpgrade = async (
  sender: Signer,
  contract: Contract,
  args: Array<ContractParam>,
  proxyAdmin: Contract,
  proxyAddress: string,
  buildAcceptTx = false,
) => {
  const initTx = args ? await contract.populateTransaction.initialize(...args) : null
  const acceptFunctionName = initTx ? 'acceptProxyAndCall' : 'acceptProxy'
  const acceptFunctionParams = initTx
    ? [contract.address, proxyAddress, initTx.data]
    : [contract.address, proxyAddress]

  if (buildAcceptTx) {
    console.info(
      `
      Copy this data in the Gnosis Multisig UI, or a similar app and call ${acceptFunctionName}
      --------------------------------------------------------------------------------------
        > Contract Address:  ${proxyAdmin.address}
        > Implementation:    ${contract.address}
        > Proxy:             ${proxyAddress}
        > Data:              ${initTx && initTx.data}
      `,
    )
  } else {
    await proxyAdmin.connect(sender)[acceptFunctionName](...acceptFunctionParams)
  }
}

// Get the proxy admin to own the proxy for this contract
function getProxyAdmin(addressBook: AddressBook): Contract {
  const proxyAdminEntry = addressBook.getEntry('GraphProxyAdmin')
  if (!proxyAdminEntry) {
    throw new Error('GraphProxyAdmin not detected in the config, must be deployed first!')
  }
  return loadContractAt('GraphProxyAdmin', proxyAdminEntry.address, getArtifactsPath())
}

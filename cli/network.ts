import { LinkReferences } from 'hardhat/types'

import {
  providers,
  utils,
  Contract,
  ContractFactory,
  ContractTransaction,
  Signer,
  Overrides,
  BigNumber,
  PayableOverrides,
  Wallet,
} from 'ethers'

import { logger } from './logging'
import { AddressBook } from './address-book'
import { loadArtifact } from './artifacts'
import { defaultOverrides } from './defaults'
import { GraphToken } from '../build/types/GraphToken'

const { keccak256, randomBytes, parseUnits, hexlify } = utils

export const randomHexBytes = (n = 32): string => hexlify(randomBytes(n))
export const toBN = (value: string | number | BigNumber): BigNumber => BigNumber.from(value)
export const toGRT = (value: string | number): BigNumber => {
  return parseUnits(typeof value === 'number' ? value.toString() : value, '18')
}
export const getProvider = (providerUrl: string, network?: number): providers.JsonRpcProvider =>
  new providers.JsonRpcProvider(providerUrl, network)

export const getChainID = (): number => {
  return 4 // Only works for rinkeby right now
}

export const hashHexString = (input: string): string => keccak256(`0x${input.replace(/^0x/, '')}`)

type ContractParam = string | BigNumber | number
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
  logger.info(`Checking for valid ${name} contract...`)
  if (!address || address === '') {
    logger.warn('This contract is not in our address book.')
    return false
  }

  const addressEntry = addressBook.getEntry(name)

  // If the contract is behind a proxy we check the Proxy artifact instead
  const artifact = addressEntry.proxy === true ? loadArtifact('GraphProxy') : loadArtifact(name)

  if (checkCreationCode) {
    const savedCreationCodeHash = addressEntry.creationCodeHash
    const creationCodeHash = hashHexString(artifact.bytecode)
    if (!savedCreationCodeHash || savedCreationCodeHash !== creationCodeHash) {
      logger.warn(`creationCodeHash in our address book doesn't match ${name} artifacts`)
      logger.info(`${savedCreationCodeHash} !== ${creationCodeHash}`)
      return false
    }
  }

  const savedRuntimeCodeHash = addressEntry.runtimeCodeHash
  const runtimeCodeHash = hashHexString(await provider.getCode(address))
  if (runtimeCodeHash === hashHexString('0x00') || runtimeCodeHash === hashHexString('0x')) {
    logger.warn('No runtimeCode exists at the address in our address book')
    return false
  }
  if (savedRuntimeCodeHash !== runtimeCodeHash) {
    logger.warn(`runtimeCodeHash for ${address} does not match what's in our address book`)
    logger.info(`${savedRuntimeCodeHash} !== ${runtimeCodeHash}`)
    return false
  }
  return true
}

export const waitTransaction = async (
  sender: Signer,
  tx: ContractTransaction,
): Promise<providers.TransactionReceipt> => {
  const receipt = await sender.provider.waitForTransaction(tx.hash)
  const networkName = (await sender.provider.getNetwork()).name
  if (networkName === 'goerli') {
    receipt.status // 1 = success, 0 = failure
      ? logger.info(`Transaction succeeded: 'https://${networkName}.etherscan.io/tx/${tx.hash}'`)
      : logger.warn(`Transaction failed: 'https://${networkName}.etherscan.io/tx/${tx.hash}'`)
  } else {
    receipt.status
      ? logger.info(`Transaction succeeded: ${tx.hash}`)
      : logger.warn(`Transaction failed: ${tx.hash}`)
  }
  return receipt
}

export const sendTransaction = async (
  sender: Signer,
  contract: Contract,
  fn: string,
  // eslint-disable-next-line  @typescript-eslint/no-explicit-any
  params?: Array<any>,
  overrides?: PayableOverrides,
): Promise<providers.TransactionReceipt> => {
  // Setup overrides
  if (overrides) {
    params.push(overrides)
  } else {
    params.push(defaultOverrides)
  }

  // Send transaction
  const tx: ContractTransaction = await contract.connect(sender).functions[fn](...params)
  if (tx === undefined) {
    logger.error(
      `It appears the function does not exist on this contract, or you have the wrong contract address`,
    )
    throw new Error('Transaction error')
  }
  logger.info(
    `> Sent transaction ${fn}: [${params.slice(0, -1)}] \n  contract: ${
      contract.address
    }\n  txHash: ${tx.hash}`,
  )

  // Wait for transaction to be mined
  return waitTransaction(sender, tx)
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

export const getContractAt = (
  name: string,
  address: string,
  signerOrProvider?: Signer | providers.Provider,
): Contract => {
  return new Contract(address, loadArtifact(name).abi, signerOrProvider)
}

export const deployProxy = async (
  implementationAddress: string,
  proxyAdminAddress: string,
  sender: Signer,
  overrides?: Overrides,
): Promise<DeployResult> => {
  return deployContract(
    'GraphProxy',
    [implementationAddress, proxyAdminAddress],
    sender,
    false,
    overrides,
  )
}

export const deployContract = async (
  name: string,
  args: Array<ContractParam>,
  sender: Signer,
  autolink = true,
  overrides?: Overrides,
): Promise<DeployResult> => {
  // This function will autolink, that means it will automatically deploy external libraries
  // and link them to the contract
  const libraries = {}
  if (autolink) {
    const artifact = loadArtifact(name)
    if (artifact.linkReferences && Object.keys(artifact.linkReferences).length > 0) {
      for (const fileReferences of Object.values(artifact.linkReferences)) {
        for (const libName of Object.keys(fileReferences)) {
          const deployResult = await deployContract(libName, [], sender, false, overrides)
          libraries[libName] = deployResult.contract.address
        }
      }
    }
  }

  // Deploy
  const factory = getContractFactory(name, libraries)
  const contract = await factory.connect(sender).deploy(...args)
  const txHash = contract.deployTransaction.hash
  logger.info(`> Deploy ${name}, txHash: ${txHash}`)
  await sender.provider.waitForTransaction(txHash)

  // Receipt
  const creationCodeHash = hashHexString(factory.bytecode)
  const runtimeCodeHash = hashHexString(await sender.provider.getCode(contract.address))
  logger.info(`= CreationCodeHash: ${creationCodeHash}`)
  logger.info(`= RuntimeCodeHash: ${runtimeCodeHash}`)
  logger.info(`${name} has been deployed to address: ${contract.address}`)

  return { contract, creationCodeHash, runtimeCodeHash, txHash, libraries }
}

export const deployContractWithProxy = async (
  proxyAdmin: Contract,
  name: string,
  args: Array<ContractParam>,
  sender: Signer,
  buildAcceptProxyTx = false,
  overrides?: Overrides,
): Promise<Contract> => {
  // Deploy implementation
  const { contract } = await deployContract(name, [], sender, true, overrides)

  // Wrap implementation with proxy
  const proxy = await wrapContractWithProxy(
    proxyAdmin,
    contract,
    args,
    sender,
    buildAcceptProxyTx,
    overrides,
  )

  // Use interface of contract but with the proxy address
  return contract.attach(proxy.address)
}

export const wrapContractWithProxy = async (
  proxyAdmin: Contract,
  contract: Contract,
  args: Array<ContractParam>,
  sender: Signer,
  buildAcceptProxyTx = false,
  overrides?: Overrides,
): Promise<Contract> => {
  // Deploy proxy
  const { contract: proxy } = await deployProxy(
    contract.address,
    proxyAdmin.address,
    sender,
    overrides,
  )

  // Implementation accepts upgrade
  const initTx = args ? await contract.populateTransaction.initialize(...args) : null
  const acceptFunctionName = initTx ? 'acceptProxyAndCall' : 'acceptProxy'
  const acceptFunctionParams = initTx
    ? [contract.address, proxy.address, initTx.data]
    : [contract.address, proxy.address]
  if (buildAcceptProxyTx) {
    logger.info(
      ` 
      Copy this data in the Gnosis Multisig UI, or a similar app and call ${acceptFunctionName}
      --------------------------------------------------------------------------------------
        > Contract Address:  ${proxyAdmin.address}
        > Implementation:    ${contract.address}
        > Proxy:             ${proxy.address}
        > Data:              ${initTx && initTx.data}
      `,
    )
  } else {
    await sendTransaction(sender, proxyAdmin, acceptFunctionName, acceptFunctionParams)
  }

  return proxy
}

export const deployContractAndSave = async (
  name: string,
  args: Array<ContractParam>,
  sender: Signer,
  addressBook: AddressBook,
): Promise<Contract> => {
  // Deploy the contract
  const deployResult = await deployContract(name, args, sender)

  // Save address entry
  addressBook.setEntry(name, {
    address: deployResult.contract.address,
    constructorArgs: args.length === 0 ? undefined : args.map((e) => e.toString()),
    creationCodeHash: deployResult.creationCodeHash,
    runtimeCodeHash: deployResult.runtimeCodeHash,
    txHash: deployResult.txHash,
    libraries:
      deployResult.libraries && Object.keys(deployResult.libraries).length > 0
        ? deployResult.libraries
        : undefined,
  })
  logger.info('> Contract saved to address book')

  return deployResult.contract
}

export const deployContractWithProxyAndSave = async (
  name: string,
  args: Array<ContractParam>,
  sender: Signer,
  addressBook: AddressBook,
  buildAcceptProxyTx?: boolean,
): Promise<Contract> => {
  // Get the GraphProxyAdmin to own the GraphProxy for this contract
  const proxyAdminEntry = addressBook.getEntry('GraphProxyAdmin')
  if (!proxyAdminEntry) {
    throw new Error('GraphProxyAdmin not detected in the config, must be deployed first!')
  }
  const proxyAdmin = getContractAt('GraphProxyAdmin', proxyAdminEntry.address)

  // Deploy implementation
  const contract = await deployContractAndSave(name, [], sender, addressBook)

  // Wrap implementation with proxy
  const proxy = await wrapContractWithProxy(proxyAdmin, contract, args, sender, buildAcceptProxyTx)

  // Overwrite address entry with proxy
  const artifact = loadArtifact('GraphProxy')
  const contractEntry = addressBook.getEntry(name)
  addressBook.setEntry(name, {
    address: proxy.address,
    initArgs: args.length === 0 ? undefined : args.map((e) => e.toString()),
    creationCodeHash: hashHexString(artifact.bytecode),
    runtimeCodeHash: hashHexString(await sender.provider.getCode(proxy.address)),
    txHash: proxy.deployTransaction.hash,
    proxy: true,
    implementation: contractEntry,
  })
  logger.info('> Contract saved to address book')

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
      for (const fileReferences of Object.values(artifact.linkReferences)) {
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

export const ensureAllowance = async (
  sender: Wallet,
  spenderAddress: string,
  token: GraphToken,
  amount: BigNumber,
) => {
  // check balance
  const senderBalance = await token.balanceOf(sender.address)
  if (senderBalance.lt(amount)) {
    throw new Error('Sender balance is insufficient for the transfer')
  }

  // check allowance
  const allowance = await token.allowance(sender.address, spenderAddress)
  if (allowance.gte(amount)) {
    return
  }

  // approve
  logger.info('Approving token transfer')
  return sendTransaction(sender, token, 'approve', [spenderAddress, amount])
}

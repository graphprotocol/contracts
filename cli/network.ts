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
} from 'ethers'
import consola from 'consola'

import { AddressBook } from './address-book'
import { loadArtifact } from './artifacts'
import { defaultOverrides } from './defaults'

const { keccak256, randomBytes, parseUnits, hexlify } = utils

export const logger = consola.create({})

export const randomHexBytes = (n = 32): string => hexlify(randomBytes(n))
export const toGRT = (value: string | number): BigNumber => {
  return parseUnits(typeof value === 'number' ? value.toString() : value, '18')
}
export const getProvider = (providerUrl: string, network?: number): providers.JsonRpcProvider =>
  new providers.JsonRpcProvider(providerUrl, network)

export const getChainID = (): number => {
  return 4 // Only works for rinkeby right now
}

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

export const waitTransaction = async (
  sender: Signer,
  tx: ContractTransaction,
): Promise<providers.TransactionReceipt> => {
  const receipt = await sender.provider.waitForTransaction(tx.hash)
  const networkName = (await sender.provider.getNetwork()).name
  if (networkName === 'kovan' || networkName === 'rinkeby') {
    receipt.status // 1 = success, 0 = failure
      ? logger.success(`Transaction succeeded: 'https://${networkName}.etherscan.io/tx/${tx.hash}'`)
      : logger.warn(`Transaction failed: 'https://${networkName}.etherscan.io/tx/${tx.hash}'`)
  } else {
    receipt.status
      ? logger.success(`Transaction succeeded: ${tx.hash}`)
      : logger.warn(`Transaction failed: ${tx.hash}`)
  }
  return receipt
}

export const sendTransaction = async (
  sender: Signer,
  contract: Contract,
  fn: string,
  params?: Array<any>,
  overrides?: Overrides,
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
  logger.log(
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

export const deployProxyAndAccept = async () => {}

export const deployContract = async (
  name: string,
  args: Array<any>,
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
  logger.log(`> Deploy ${name}, txHash: ${txHash}`)
  await sender.provider.waitForTransaction(txHash)

  // Receipt
  const creationCodeHash = hash(factory.bytecode)
  const runtimeCodeHash = hash(await sender.provider.getCode(contract.address))
  logger.log('= CreationCodeHash: ', creationCodeHash)
  logger.log('= RuntimeCodeHash: ', runtimeCodeHash)
  logger.success(`${name} has been deployed to address: ${contract.address}`)

  return { contract, creationCodeHash, runtimeCodeHash, txHash, libraries }
}

export const deployContractWithProxy = async (
  proxyAdmin: Contract,
  name: string,
  args: Array<any>,
  sender: Signer,
  autolink = true,
  buildAcceptProxyTx = false,
  overrides?: Overrides,
): Promise<Contract> => {
  // Deploy implementation
  const { contract } = await deployContract(name, [], sender, autolink, overrides)
  // Deploy proxy
  const { contract: proxy } = await deployProxy(
    contract.address,
    proxyAdmin.address,
    sender,
    overrides,
  )
  // Implementation accepts upgrade
  if (args) {
    const initTx = await contract.populateTransaction.initialize(...args)
    if (buildAcceptProxyTx) {
      logger.log(
        `
        Copy this data in the gnosis multisig UI, or a similar app and call acceptProxyAndCall
          contract address:  ${proxyAdmin.address}
          implementation:    ${contract.address}
          proxy:             ${proxy.address}
          data:              ${initTx.data}
          `,
      )
    } else {
      await sendTransaction(sender, proxyAdmin, 'acceptProxyAndCall', [
        contract.address,
        proxy.address,
        initTx.data,
      ])
    }
  } else {
    if (buildAcceptProxyTx) {
      logger.log(
        `
        Copy this data in the gnosis multisig UI, or a similar app and call acceptProxy
          contract address:  ${proxyAdmin.address}
          implementation:    ${contract.address}
          proxy:             ${proxy.address}
        `,
      )
    } else {
      await sendTransaction(sender, proxyAdmin, 'acceptProxy', [contract.address, proxy.address])
    }
  }
  return contract.attach(proxy.address)
}

export const deployContractAndSave = async (
  name: string,
  args: Array<any>,
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
  logger.log('> Contract saved to address book')

  return deployResult.contract
}

export const deployContractWithProxyAndSave = async (
  name: string,
  args: Array<any>,
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
  // Deploy proxy
  const { contract: proxy } = await deployProxy(contract.address, proxyAdmin.address, sender)
  // Implementation accepts upgrade
  if (args) {
    const initTx = args[0].name
      ? await contract.populateTransaction.initialize(...args.map((a) => a.value)) // just get values
      : await contract.populateTransaction.initialize(...args) // already just a value array
    if (buildAcceptProxyTx) {
      logger.log(
        `
        Copy this data in the gnosis multisig UI, or a similar app and call acceptProxyAndCall
          contract address:  ${proxyAdmin.address}
          implementation:    ${contract.address}
          proxy:             ${proxy.address}
          data:              ${initTx.data}
        `,
      )
    } else {
      await sendTransaction(sender, proxyAdmin, 'acceptProxyAndCall', [
        contract.address,
        proxy.address,
        initTx.data,
      ])
    }
  } else {
    if (buildAcceptProxyTx) {
      logger.log(
        `
        Copy this data in the gnosis multisig UI, or a similar app and call acceptProxy
          contract address:  ${proxyAdmin.address}
          implementation:    ${contract.address}
          proxy:             ${proxy.address}
        `,
      )
    } else {
      await sendTransaction(sender, proxyAdmin, 'acceptProxy', [contract.address, proxy.address])
    }
  }

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
  logger.log('> Contract saved to address book')

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

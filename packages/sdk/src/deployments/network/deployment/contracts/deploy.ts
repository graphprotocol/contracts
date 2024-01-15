import {
  deployContractImplementationAndSave,
  deployContractWithProxy,
  deployContractWithProxyAndSave,
} from './proxy'
import { deployContract, deployContractAndSave } from '../../../lib/deploy/contract'
import { DeployType, isDeployType } from '../../../lib/types/deploy'
import { confirm } from '../../../../utils/prompt'
import { assertObject } from '../../../../utils/assertions'
import { type GraphChainId, isGraphL1ChainId, isGraphL2ChainId } from '../../../../chain'
import {
  GraphNetworkSharedContractNameList,
  type GraphNetworkContractName,
  GraphNetworkL1ContractNameList,
  GraphNetworkL2ContractNameList,
  GraphNetworkGovernedContractNameList,
} from './list'
import { getContractConfig, loadCallParams, readConfig } from '../../../lib/config'
import { logDebug } from '../../../logger'

import type { ContractTransaction, Signer, providers } from 'ethers'
import type { DeployData, DeployResult } from '../../../lib/types/deploy'
import type { AddressBook } from '../../../lib/address-book'
import { GraphNetworkAddressBook } from '../address-book'
import { isContractDeployed } from '../../../lib/deploy/deploy'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { Contract, Wallet, ethers } from 'ethers'
import { acceptOwnership } from '../../actions/governed'
import { setPausedProtocol } from '../../actions/pause'
import { GraphNetworkContracts, loadGraphNetworkContracts } from './load'
import { setCode } from '../../../../helpers/code'
import { logContractCall, logContractReceipt } from '../../../lib/contracts/log'

export async function deployGraphNetwork(
  addressBookPath: string,
  graphConfigPath: string,
  chainId: GraphChainId,
  deployer: SignerWithAddress,
  provider: providers.Provider,
  opts?: {
    governor?: SignerWithAddress
    skipConfirmation?: boolean
    forceDeploy?: boolean
    buildAcceptTx?: boolean
    l2Deploy?: boolean
    enableTxLogging?: boolean
  },
): Promise<GraphNetworkContracts | undefined> {
  // Opts
  const governor = opts?.governor ?? undefined
  const skipConfirmation = opts?.skipConfirmation ?? false
  const forceDeploy = opts?.forceDeploy ?? false
  const buildAcceptTx = opts?.buildAcceptTx ?? false
  const l2Deploy = opts?.l2Deploy ?? false
  const enableTxLogging = opts?.enableTxLogging ?? true

  // Snapshot deployer
  const beforeDeployerNonce = await deployer.getTransactionCount()
  const beforeDeployerBalance = await deployer.getBalance()

  // Ensure action
  const sure = await confirm('Are you sure you want to migrate contracts?', skipConfirmation)
  if (!sure) return

  // Build list of contracts to deploy
  // We force AllocationExchange to the end, it requires GraphToken and Staking to be deployed beforehand
  const contractList: GraphNetworkContractName[] = [
    ...GraphNetworkSharedContractNameList.filter((c) => c !== 'AllocationExchange'),
  ]
  if (!l2Deploy && isGraphL1ChainId(chainId)) {
    contractList.push(...GraphNetworkL1ContractNameList)
  }
  if (l2Deploy || isGraphL2ChainId(chainId)) {
    contractList.push(...GraphNetworkL2ContractNameList)
  }
  contractList.push('AllocationExchange')

  logDebug(`>>> Migrating contracts <<<\n`)

  ////////////////////////////////////////
  // Deploy contracts
  ////////////////////////////////////////

  logDebug(`>>> Contracts deployment\n`)

  const graphConfig = readConfig(graphConfigPath)
  const addressBook = new GraphNetworkAddressBook(addressBookPath, chainId)

  const pendingContractCalls = []
  const contracts = []
  for (const name of contractList) {
    // Get address book info
    const addressEntry = addressBook.getEntry(name)
    const savedAddress = addressEntry && addressEntry.address

    logDebug(`= Deploy: ${name}`)

    // Check if contract already deployed
    if (!forceDeploy) {
      const isDeployed = await isContractDeployed(
        name,
        'GraphProxy',
        savedAddress,
        addressBook,
        provider,
      )
      if (isDeployed) {
        logDebug(`${name} is up to date, no action required`)
        logDebug(`Address: ${savedAddress}\n`)
        continue
      }
    }

    // Get config and deploy contract
    const contractConfig = getContractConfig(graphConfig, addressBook, name, deployer.address)
    const contract = await deploy(
      contractConfig.proxy ? DeployType.DeployWithProxyAndSave : DeployType.DeployAndSave,
      deployer,
      {
        name: name,
        args: contractConfig.params.map((a) => a.value),
      },
      addressBook,
      {
        name: 'GraphProxy',
        opts: {
          buildAcceptTx: buildAcceptTx,
        },
      },
    )
    contracts.push({ contract: contract, name: name })
    logDebug('')

    // Defer contract calls after deploying every contract
    if (contractConfig.calls) {
      pendingContractCalls.push({ name, contract, calls: contractConfig.calls })
    }
  }
  logDebug('Contract deployments done! Contract calls are next')

  ////////////////////////////////////////
  // Run contracts calls
  ////////////////////////////////////////
  logDebug('')
  logDebug(`>>> Contracts calls\n`)
  if (pendingContractCalls.length > 0) {
    for (const entry of pendingContractCalls) {
      if (entry.calls.length == 0) continue

      logDebug(`= Config: ${entry.name}`)
      for (const call of entry.calls) {
        logDebug(`* Calling ${call.fn}`)
        try {
          const params = loadCallParams(call.params, addressBook, deployer.address)
          logDebug(`- Params: ${params.join(', ')}`)
          const overrides = process.env.CI ? { gasLimit: 2_000_000 } : {}
          const response: ContractTransaction = await entry.contract.contract
            .connect(deployer)
            .functions[call.fn](...params, overrides)
          logContractCall(response, entry.name, call.fn, params)
          const receipt = await entry.contract.contract.provider.waitForTransaction(response.hash)
          logContractReceipt(receipt)
        } catch (error) {
          // TODO: can we clean this up?
          // Fallback for StakingExtension methods
          if (['L1Staking', 'L2Staking'].includes(entry.name)) {
            const StakingExtension = contracts.find((c) => c.name === 'StakingExtension')
            if (StakingExtension === undefined) {
              throw new Error('StakingExtension not found')
            }
            const ExtendedStaking = new Contract(
              entry.contract.contract.address,
              StakingExtension.contract.contract.interface,
              deployer,
            )
            await ExtendedStaking.connect(deployer).functions[call.fn](
              ...loadCallParams(call.params, addressBook, deployer.address),
            )
          } else {
            throw error
          }
        }
      }
      logDebug('')
    }
  } else {
    logDebug('Nothing to do')
  }

  ////////////////////////////////////////
  // Load contracts
  ////////////////////////////////////////
  const loadedContracts = loadGraphNetworkContracts(addressBookPath, chainId, provider, undefined, {
    l2Load: l2Deploy,
    enableTxLogging: enableTxLogging,
  })

  ////////////////////////////////////////
  // Post deploy
  ////////////////////////////////////////
  // If a governor was provided, accept ownership of contracts and unpause the protocol
  if (governor) {
    const txs: ContractTransaction[] = []
    for (const contract of GraphNetworkGovernedContractNameList) {
      const tx = await acceptOwnership(loadedContracts, governor, { contractName: contract })
      if (tx) {
        txs.push()
      }
    }
    await Promise.all(txs.map((tx) => tx.wait()))
    await setPausedProtocol(loadedContracts, governor, { paused: false })
  }

  ////////////////////////////////////////
  // Print summary
  ////////////////////////////////////////
  logDebug('')
  logDebug(`>>> Summary\n`)
  logDebug('All done!')

  const afterDeployerNonce = await deployer.getTransactionCount()
  const afterDeployerBalance = await deployer.getBalance()

  const spent = ethers.utils.formatEther(beforeDeployerBalance.sub(afterDeployerBalance))
  const nTx = afterDeployerNonce - beforeDeployerNonce
  logDebug(
    `Sent ${nTx} transaction${nTx === 1 ? '' : 's'} & spent ${
      ethers.constants.EtherSymbol
    } ${spent}`,
  )

  return loadedContracts
}

export async function deployMockGraphNetwork(l2Deploy: boolean) {
  // Contract list
  const contractList: GraphNetworkContractName[] = [
    ...GraphNetworkSharedContractNameList.filter((c) => c !== 'AllocationExchange'),
  ]
  contractList.push(...(l2Deploy ? GraphNetworkL2ContractNameList : GraphNetworkL1ContractNameList))
  contractList.push('AllocationExchange')

  const contracts: any = {}
  for (const name of contractList) {
    const fake = Wallet.createRandom()
    await setCode(fake.address, '0x1234')
    contracts[name] = new Contract(fake.address, [], fake)
  }

  return contracts as GraphNetworkContracts // :eyes:
}

export const deploy = async (
  type: DeployType | unknown,
  sender: Signer,
  contractData: DeployData,
  addressBook?: AddressBook,
  proxyData?: DeployData,
): Promise<DeployResult> => {
  if (!isDeployType(type)) {
    throw new Error('Please provide the correct option for deploy type')
  }

  switch (type) {
    case DeployType.Deploy:
      logDebug(`Deploying contract ${contractData.name}...`)
      return await deployContract(sender, contractData)
    case DeployType.DeployAndSave:
      logDebug(`Deploying contract ${contractData.name} and saving to address book...`)
      assertObject(addressBook)
      return await deployContractAndSave(sender, contractData, addressBook)
    case DeployType.DeployWithProxy:
      logDebug(`Deploying contract ${contractData.name} with proxy ...`)
      assertObject(addressBook)
      validateProxyData(proxyData)
      // TODO - for some reason proxyData's type is not being narrowed down to DeployData
      // so we force non-null assertion
      return await deployContractWithProxy(sender, contractData, addressBook, proxyData!)
    case DeployType.DeployWithProxyAndSave:
      logDebug(`Deploying contract ${contractData.name} with proxy and saving to address book...`)
      assertObject(addressBook)
      validateProxyData(proxyData)
      // TODO - for some reason proxyData's type is not being narrowed down to DeployData
      // so we force non-null assertion
      return await deployContractWithProxyAndSave(sender, contractData, addressBook, proxyData!)
    case DeployType.DeployImplementationAndSave:
      logDebug(
        `Deploying contract ${contractData.name} implementation and saving to address book...`,
      )
      assertObject(addressBook)
      validateProxyData(proxyData)
      // TODO - for some reason proxyData's type is not being narrowed down to DeployData
      // so we force non-null assertion
      return await deployContractImplementationAndSave(
        sender,
        contractData,
        addressBook,
        proxyData!,
      )
    default:
      throw new Error('Please provide the correct option for deploy type')
  }
}

function validateProxyData(proxyData: DeployData | undefined): void {
  if (!proxyData) {
    throw new Error('Proxy data not provided!')
  }
}

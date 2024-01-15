import { Contract, providers, Signer } from 'ethers'
import path from 'path'

import {
  GraphNetworkL1ContractNameList,
  GraphNetworkL2ContractNameList,
  GraphNetworkOptionalContractNameList,
  GraphNetworkSharedContractNameList,
  isGraphNetworkContractName,
} from './list'
import { GraphNetworkAddressBook } from '../address-book'
import { loadContract, loadContracts } from '../../../lib/contracts/load'
import { isGraphChainId, isGraphL1ChainId, isGraphL2ChainId } from '../../../..'
import { assertObject } from '../../../../utils/assertions'

import type { GraphChainId } from '../../../..'
import type { GraphNetworkContractName } from './list'

import type {
  EpochManager,
  DisputeManager,
  ServiceRegistry,
  Curation,
  RewardsManager,
  GraphProxyAdmin,
  GraphToken,
  Controller,
  BancorFormula,
  IENS,
  AllocationExchange,
  SubgraphNFT,
  SubgraphNFTDescriptor,
  GraphCurationToken,
  L1GraphTokenGateway,
  L2GraphToken,
  L2GraphTokenGateway,
  BridgeEscrow,
  L1Staking,
  L2Staking,
  L1GNS,
  L2GNS,
  L2Curation,
  StakingExtension,
} from '@graphprotocol/contracts'
import { ContractList } from '../../../lib/types/contract'
import { loadArtifact } from '../../../lib/deploy/artifacts'
import { mergeABIs } from '../../../../utils/abi'

export type L1ExtendedStaking = L1Staking & StakingExtension
export type L2ExtendedStaking = L2Staking & StakingExtension

export interface GraphNetworkContracts extends ContractList<GraphNetworkContractName> {
  EpochManager: EpochManager
  DisputeManager: DisputeManager
  ServiceRegistry: ServiceRegistry
  RewardsManager: RewardsManager
  GraphProxyAdmin: GraphProxyAdmin
  Controller: Controller
  BancorFormula: BancorFormula
  AllocationExchange: AllocationExchange
  SubgraphNFT: SubgraphNFT
  SubgraphNFTDescriptor: SubgraphNFTDescriptor
  GraphCurationToken: GraphCurationToken
  StakingExtension: StakingExtension
  IENS?: IENS

  // Only L1
  L1GraphToken?: GraphToken
  L1Staking?: L1Staking
  L1GNS?: L1GNS
  L1Curation?: Curation
  L1GraphTokenGateway?: L1GraphTokenGateway
  BridgeEscrow?: BridgeEscrow

  // Only L2
  L2GraphToken?: L2GraphToken
  L2Staking?: L2Staking
  L2GNS?: L2GNS
  L2Curation?: L2Curation
  L2GraphTokenGateway?: L2GraphTokenGateway

  // Alias
  GNS: L1GNS | L2GNS
  Staking: L1ExtendedStaking | L2ExtendedStaking
  GraphToken: GraphToken | L2GraphToken
  Curation: Curation | L2Curation
  GraphTokenGateway: L1GraphTokenGateway | L2GraphTokenGateway

  // Iterator
  [Symbol.iterator]: () => Generator<Contract, void, void>
}

// This ensures that local artifacts are preferred over the ones that ship with the sdk in node_modules
export function getArtifactsPath() {
  return [
    path.resolve('build/contracts'),
    path.resolve('node_modules', '@graphprotocol/contracts/build/contracts'),
  ]
}
export function loadGraphNetworkContracts(
  addressBookPath: string,
  chainId: number,
  signerOrProvider?: Signer | providers.Provider,
  artifactsPath?: string | string[],
  opts?: {
    enableTxLogging?: boolean
    strictAssert?: boolean
    l2Load?: boolean
  },
): GraphNetworkContracts {
  artifactsPath = artifactsPath ?? getArtifactsPath()
  if (!isGraphChainId(chainId)) {
    throw new Error(`ChainId not supported: ${chainId}`)
  }
  const addressBook = new GraphNetworkAddressBook(addressBookPath, chainId)
  const contracts = loadContracts<GraphChainId, GraphNetworkContractName>(
    addressBook,
    artifactsPath,
    signerOrProvider,
    opts?.enableTxLogging ?? true,
    GraphNetworkOptionalContractNameList as unknown as GraphNetworkContractName[], // This is ugly but safe
  )

  assertGraphNetworkContracts(contracts, chainId, opts?.strictAssert)

  // Alias
  // One of L1/L2 should always be defined so we can safely assert the types
  const loadL1 = isGraphL1ChainId(chainId) && !opts?.l2Load
  contracts.GraphToken = loadL1 ? contracts.GraphToken! : contracts.L2GraphToken!
  contracts.GNS = loadL1 ? contracts.L1GNS! : contracts.L2GNS!
  contracts.Curation = loadL1 ? contracts.Curation! : contracts.L2Curation!
  contracts.GraphTokenGateway = loadL1
    ? contracts.L1GraphTokenGateway!
    : contracts.L2GraphTokenGateway!

  // Staking is a special snowflake!
  // Since staking contract is a proxy for StakingExtension we need to manually
  // merge the ABIs and override the contract instance
  const stakingName = loadL1 ? 'L1Staking' : 'L2Staking'
  const staking = contracts[stakingName]
  if (staking) {
    const stakingOverride = loadContract(
      stakingName,
      addressBook,
      artifactsPath,
      signerOrProvider,
      opts?.enableTxLogging ?? true,
      new Contract(
        staking.address,
        mergeABIs(
          loadArtifact(stakingName, artifactsPath).abi,
          loadArtifact('StakingExtension', artifactsPath).abi,
        ),
        signerOrProvider,
      ),
    ) as L1ExtendedStaking | L2ExtendedStaking
    contracts.Staking = stakingOverride
    if (loadL1) contracts.L1Staking = stakingOverride as L1ExtendedStaking
    if (!loadL1) contracts.L2Staking = stakingOverride as L2ExtendedStaking
  }

  // Iterator
  contracts[Symbol.iterator] = function* () {
    for (const key of Object.keys(this)) {
      yield this[key as GraphNetworkContractName] as Contract
    }
  }

  return contracts
}

function assertGraphNetworkContracts(
  contracts: unknown,
  chainId: GraphChainId,
  strictAssert?: boolean,
): asserts contracts is GraphNetworkContracts {
  assertObject(contracts)

  // Allow loading contracts not defined in GraphNetworkContractNameList but raise a warning
  const contractNames = Object.keys(contracts)
  if (!contractNames.every((c) => isGraphNetworkContractName(c))) {
    console.warn(
      `Loaded invalid GraphNetworkContract: ${contractNames.filter(
        (c) => !isGraphNetworkContractName(c),
      )}`,
    )
  }

  // Assert that all shared GraphNetworkContracts were loaded
  for (const contractName of GraphNetworkSharedContractNameList) {
    if (!contracts[contractName]) {
      const errMessage = `Missing GraphNetworkContract: ${contractName} for chainId ${chainId}`
      console.error(errMessage)
      if (strictAssert) {
        throw new Error(errMessage)
      }
    }
  }

  // Assert that L1/L2 specific GraphNetworkContracts were loaded
  const layerSpecificContractNames = isGraphL1ChainId(chainId)
    ? GraphNetworkL1ContractNameList
    : GraphNetworkL2ContractNameList
  for (const contractName of layerSpecificContractNames) {
    if (!contracts[contractName]) {
      const errMessage = `Missing GraphNetworkContract: ${contractName} for chainId ${chainId}`
      console.error(errMessage)
      if (strictAssert) {
        throw new Error(errMessage)
      }
    }
  }
}

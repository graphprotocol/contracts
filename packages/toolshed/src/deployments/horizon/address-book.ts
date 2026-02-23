import type { LegacyRewardsManager, LegacyStaking } from '@graphprotocol/interfaces'
import { getInterface } from '@graphprotocol/interfaces'
import { Provider, Signer } from 'ethers'
import { Contract } from 'ethers'

import { assertObject } from '../../lib/assert'
import { logDebug, logError } from '../../lib/logger'
import { AddressBook } from '../address-book'
import { wrapTransactionCalls } from '../tx-logging'
import type { GraphHorizonContractName, GraphHorizonContracts } from './contracts'
import { GraphHorizonContractNameList } from './contracts'

export class GraphHorizonAddressBook extends AddressBook<number, GraphHorizonContractName> {
  isContractName(name: unknown): name is GraphHorizonContractName {
    return typeof name === 'string' && GraphHorizonContractNameList.includes(name as GraphHorizonContractName)
  }

  loadContracts(signerOrProvider?: Signer | Provider, enableTxLogging?: boolean): GraphHorizonContracts {
    logDebug('Loading Graph Horizon contracts...')

    const contracts = this._loadContracts(signerOrProvider, enableTxLogging)

    this._assertGraphHorizonContracts(contracts)

    // Aliases
    contracts.GraphToken = contracts.L2GraphToken
    contracts.Curation = contracts.L2Curation
    contracts.GNS = contracts.L2GNS

    if (contracts.HorizonStaking) {
      // add LegacyStaking alias using old IL2Staking abi
      const contract = new Contract(contracts.HorizonStaking.target, getInterface('IL2Staking'), signerOrProvider)
      contracts.LegacyStaking = (enableTxLogging
        ? wrapTransactionCalls(contract, 'LegacyStaking')
        : contract) as unknown as LegacyStaking
    }

    if (contracts.RewardsManager) {
      // add LegacyRewardsManager alias using old ILegacyRewardsManager abi
      const contract = new Contract(
        contracts.RewardsManager.target,
        getInterface('ILegacyRewardsManager'),
        signerOrProvider,
      )
      contracts.LegacyRewardsManager = (enableTxLogging
        ? wrapTransactionCalls(contract, 'LegacyRewardsManager')
        : contract) as unknown as LegacyRewardsManager
    }

    return contracts
  }

  _assertGraphHorizonContracts(contracts: unknown): asserts contracts is GraphHorizonContracts {
    assertObject(contracts)

    // Assert that all GraphHorizonContracts were loaded
    for (const contractName of GraphHorizonContractNameList) {
      if (!contracts[contractName]) {
        logError(`Missing GraphHorizon contract: ${contractName}`)
      }
    }
  }
}

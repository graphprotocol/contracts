import { GraphHorizonArtifactsMap, GraphHorizonContractNameList } from './contracts'
import { logDebug, logError } from '../../lib/logger'
import { Provider, Signer } from 'ethers'
import { AddressBook } from '../address-book'
import { assertObject } from '../../lib/assert'
import { Contract } from 'ethers'
import { loadArtifact } from '../artifact'
import { mergeABIs } from '../../core/abi'
import { wrapTransactionCalls } from '../tx-logging'

import type { GraphHorizonContractName, GraphHorizonContracts } from './contracts'
import type { LegacyStaking } from './types'

export class GraphHorizonAddressBook extends AddressBook<number, GraphHorizonContractName> {
  isContractName(name: unknown): name is GraphHorizonContractName {
    return (
      typeof name === 'string'
      && GraphHorizonContractNameList.includes(name as GraphHorizonContractName)
    )
  }

  loadContracts(
    signerOrProvider?: Signer | Provider,
    enableTxLogging?: boolean,
  ): GraphHorizonContracts {
    logDebug('Loading Graph Horizon contracts...')

    const contracts = this._loadContracts(
      GraphHorizonArtifactsMap,
      signerOrProvider,
      enableTxLogging,
    )

    // rewire HorizonStaking to include HorizonStakingExtension abi
    if (contracts.HorizonStaking) {
      const stakingOverride = new Contract(
        this.getEntry('HorizonStaking').address,
        mergeABIs(
          loadArtifact('HorizonStaking', GraphHorizonArtifactsMap.HorizonStaking).abi,
          loadArtifact('HorizonStakingExtension', GraphHorizonArtifactsMap.HorizonStaking).abi,
        ),
        signerOrProvider,
      )
      contracts.HorizonStaking = enableTxLogging
        ? wrapTransactionCalls(stakingOverride, 'HorizonStaking')
        : stakingOverride
    }

    this._assertGraphHorizonContracts(contracts)

    // Aliases
    contracts.GraphToken = contracts.L2GraphToken
    contracts.Curation = contracts.L2Curation
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
    contracts.GNS = contracts.L2GNS

    if (contracts.HorizonStaking) {
      // add LegacyStaking alias using old IL2Staking abi
      const contract = new Contract(
        contracts.HorizonStaking.target,
        loadArtifact('IL2Staking', GraphHorizonArtifactsMap.LegacyStaking).abi,
        signerOrProvider,
      )
      contracts.LegacyStaking = (
        enableTxLogging
          ? wrapTransactionCalls(contract, 'LegacyStaking')
          : contract
      ) as unknown as LegacyStaking
    }

    return contracts
  }

  _assertGraphHorizonContracts(
    contracts: unknown,
  ): asserts contracts is GraphHorizonContracts {
    assertObject(contracts)

    // Assert that all GraphHorizonContracts were loaded
    for (const contractName of GraphHorizonContractNameList) {
      if (!contracts[contractName]) {
        logError(`Missing GraphHorizon contract: ${contractName}`)
      }
    }
  }
}

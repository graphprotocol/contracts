import { logDebug, logError } from '../../lib/logger'
import { Provider, Signer } from 'ethers'
import { SubgraphServiceArtifactsMap, SubgraphServiceContractNameList } from './contracts'
import { AddressBook } from '../address-book'
import { assertObject } from '../../lib/assert'
import { Contract } from 'ethers'
import { loadArtifact } from '../artifact'
import { wrapTransactionCalls } from '../tx-logging'

import type { SubgraphServiceContractName, SubgraphServiceContracts } from './contracts'
import { LegacyDisputeManager } from './types'

export class SubgraphServiceAddressBook extends AddressBook<number, SubgraphServiceContractName> {
  isContractName(name: unknown): name is SubgraphServiceContractName {
    return (
      typeof name === 'string'
      && SubgraphServiceContractNameList.includes(name as SubgraphServiceContractName)
    )
  }

  loadContracts(
    signerOrProvider?: Signer | Provider,
  ): SubgraphServiceContracts {
    logDebug('Loading Subgraph Service contracts...')

    // Filter out LegacyDisputeManager from the artifacts map
    const { LegacyDisputeManager: _, LegacyServiceRegistry: __, ...filteredArtifactsMap } = SubgraphServiceArtifactsMap

    const contracts = this._loadContracts(
      filteredArtifactsMap as typeof SubgraphServiceArtifactsMap,
      signerOrProvider,
    )

    // Aliases
    const contractsWithAliases = {
      ...contracts,
      Curation: contracts.L2Curation,
      GNS: contracts.L2GNS,

    } as SubgraphServiceContracts

    // Load LegacyDisputeManager manually
    if (this.entryExists('LegacyDisputeManager')) {
      const entry = this.getEntry('LegacyDisputeManager')
      contractsWithAliases.LegacyDisputeManager = wrapTransactionCalls(new Contract(
        entry.address,
        loadArtifact('IDisputeManager', SubgraphServiceArtifactsMap.LegacyDisputeManager).abi,
        signerOrProvider,
      ), 'LegacyDisputeManager') as unknown as LegacyDisputeManager
    }

    // Load ServiceRegistry manually
    if (this.entryExists('LegacyServiceRegistry')) {
      const entry = this.getEntry('LegacyServiceRegistry')
      contractsWithAliases.LegacyServiceRegistry = wrapTransactionCalls(new Contract(
        entry.address,
        loadArtifact('IServiceRegistry', SubgraphServiceArtifactsMap.LegacyServiceRegistry).abi,
        signerOrProvider,
      ), 'LegacyServiceRegistry') as unknown as LegacyDisputeManager
    }

    this._assertSubgraphServiceContracts(contractsWithAliases)
    return contractsWithAliases
  }

  _assertSubgraphServiceContracts(
    contracts: unknown,
  ): asserts contracts is SubgraphServiceContracts {
    assertObject(contracts)

    // Assert that all SubgraphServiceContracts were loaded
    for (const contractName of SubgraphServiceContractNameList) {
      if (!contracts[contractName]) {
        logError(`Missing SubgraphService contract: ${contractName}`)
      }
    }
  }
}

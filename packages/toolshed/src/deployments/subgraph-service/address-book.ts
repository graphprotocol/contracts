import { Provider, Signer } from 'ethers'

import { assertObject } from '../../lib/assert'
import { logDebug, logError } from '../../lib/logger'
import { AddressBook } from '../address-book'
import type { SubgraphServiceContractName, SubgraphServiceContracts } from './contracts'
import { SubgraphServiceContractNameList } from './contracts'

export class SubgraphServiceAddressBook extends AddressBook<number, SubgraphServiceContractName> {
  isContractName(name: unknown): name is SubgraphServiceContractName {
    return typeof name === 'string' && SubgraphServiceContractNameList.includes(name as SubgraphServiceContractName)
  }

  loadContracts(signerOrProvider?: Signer | Provider, enableTxLogging?: boolean): SubgraphServiceContracts {
    logDebug('Loading Subgraph Service contracts...')

    const contracts = this._loadContracts(signerOrProvider, enableTxLogging)

    this._assertSubgraphServiceContracts(contracts)

    // Aliases
    contracts.Curation = contracts.L2Curation
    contracts.GNS = contracts.L2GNS

    return contracts
  }

  _assertSubgraphServiceContracts(contracts: unknown): asserts contracts is SubgraphServiceContracts {
    assertObject(contracts)

    // Assert that all SubgraphServiceContracts were loaded
    for (const contractName of SubgraphServiceContractNameList) {
      if (!contracts[contractName]) {
        logError(`Missing SubgraphService contract: ${contractName}`)
      }
    }
  }
}

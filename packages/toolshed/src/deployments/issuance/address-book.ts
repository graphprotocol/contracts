import { Provider, Signer } from 'ethers'

import { assertObject } from '../../lib/assert'
import { logDebug, logError } from '../../lib/logger'
import { AddressBook } from '../address-book'
import type { GraphIssuanceContractName, GraphIssuanceContracts } from './contracts'
import { GraphIssuanceContractNameList } from './contracts'

export class GraphIssuanceAddressBook extends AddressBook<number, GraphIssuanceContractName> {
  isContractName(name: string): name is GraphIssuanceContractName {
    return GraphIssuanceContractNameList.includes(name as GraphIssuanceContractName)
  }

  loadContracts(signerOrProvider?: Signer | Provider, enableTxLogging?: boolean): GraphIssuanceContracts {
    logDebug('Loading Graph Issuance contracts...')

    const contracts = this._loadContracts(signerOrProvider, enableTxLogging)

    this._assertGraphIssuanceContracts(contracts)

    return contracts
  }

  _assertGraphIssuanceContracts(contracts: unknown): asserts contracts is GraphIssuanceContracts {
    assertObject(contracts)

    // Assert that all GraphIssuanceContracts were loaded
    for (const contractName of GraphIssuanceContractNameList) {
      if (!contracts[contractName]) {
        logError(`Missing GraphIssuance contract: ${contractName}`)
      }
    }
  }
}

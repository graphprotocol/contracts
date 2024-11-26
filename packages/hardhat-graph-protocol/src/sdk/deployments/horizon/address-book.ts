import { GraphHorizonArtifactsMap, GraphHorizonContractNameList } from './contracts'
import { logDebug, logError } from '../../../logger'
import { Provider, Signer } from 'ethers'
import { AddressBook } from '../../address-book'
import { assertObject } from '../../utils/assertion'

import type { GraphHorizonContractName, GraphHorizonContracts } from './contracts'

export class GraphHorizonAddressBook extends AddressBook<number, GraphHorizonContractName> {
  isContractName(name: unknown): name is GraphHorizonContractName {
    return (
      typeof name === 'string'
      && GraphHorizonContractNameList.includes(name as GraphHorizonContractName)
    )
  }

  loadContracts(
    signerOrProvider?: Signer | Provider,
  ): GraphHorizonContracts {
    logDebug('Loading Graph Horizon contracts...')

    const contracts = this._loadContracts(
      GraphHorizonArtifactsMap,
      signerOrProvider,
    )
    this._assertGraphHorizonContracts(contracts)

    // Aliases
    contracts.GraphToken = contracts.L2GraphToken
    contracts.GraphTokenGateway = contracts.L2GraphTokenGateway

    return contracts
  }

  _assertGraphHorizonContracts(
    contracts: unknown,
  ): asserts contracts is GraphHorizonContracts {
    assertObject(contracts)

    // Assert that all GraphHorizonContracts were loaded
    for (const contractName of GraphHorizonContractNameList) {
      if (!contracts[contractName]) {
        const errMessage = `Missing GraphHorizon contract: ${contractName}`
        logError(errMessage)
      }
    }
  }
}

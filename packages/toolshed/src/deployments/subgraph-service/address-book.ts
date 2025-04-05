import { Provider, Signer } from 'ethers'
import { SubgraphServiceArtifactsMap, SubgraphServiceContractNameList } from './contracts'
import { AddressBook } from '../address-book'
import { assertObject } from '../../../../hardhat-graph-protocol/src/sdk/utils/assertion'

import type { SubgraphServiceContractName, SubgraphServiceContracts } from './contracts'

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
    console.debug('Loading Subgraph Service contracts...')

    const contracts = this._loadContracts(
      SubgraphServiceArtifactsMap,
      signerOrProvider,
    )

    // Aliases
    const contractsWithAliases = {
      ...contracts,
      Curation: contracts.L2Curation,
      GNS: contracts.L2GNS,
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
        const errMessage = `Missing SubgraphService contract: ${contractName}`
        console.error(errMessage)
      }
    }
  }
}

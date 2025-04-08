import { GraphHorizonArtifactsMap, GraphHorizonContractNameList } from './contracts'
import { Provider, Signer } from 'ethers'
import { AddressBook } from '../address-book'
import { assertObject } from '../../lib/assert'
import { Contract } from 'ethers'
import { loadArtifact } from '../artifact'
import { mergeABIs } from '../../utils/abi'

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
    console.debug('Loading Graph Horizon contracts...')

    const contracts = this._loadContracts(
      GraphHorizonArtifactsMap,
      signerOrProvider,
    )

    // Handle HorizonStaking specially to include extension functions
    if (contracts.HorizonStaking) {
      const stakingOverride = new Contract(
        this.getEntry('HorizonStaking').address,
        mergeABIs(
          loadArtifact('HorizonStaking', GraphHorizonArtifactsMap.HorizonStaking).abi,
          loadArtifact('HorizonStakingExtension', GraphHorizonArtifactsMap.HorizonStaking).abi,
        ),
        signerOrProvider,
      )
      contracts.HorizonStaking = stakingOverride
    }

    this._assertGraphHorizonContracts(contracts)

    // Aliases

    contracts.GraphToken = contracts.L2GraphToken
    // contracts.GraphTokenGateway = contracts.L2GraphTokenGateway
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
    contracts.Curation = contracts.L2Curation

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
        console.error(errMessage)
      }
    }
  }
}

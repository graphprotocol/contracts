import { GraphHorizonArtifactsMap, GraphHorizonContractNameList } from './contracts'
import { logDebug, logError } from '../../../logger'
import { Provider, Signer } from 'ethers'
import { AddressBook } from '../../address-book'
import { assertObject } from '../../utils/assertion'
import { Contract } from 'ethers'
import { loadArtifact } from '../../lib/artifact'
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
    logDebug('Loading Graph Horizon contracts...')

    const contracts = this._loadContracts(
      GraphHorizonArtifactsMap,
      signerOrProvider,
    )

    // Handle HorizonStaking specially to include extension functions
    if (contracts.HorizonStaking) {
      const stakingOverride = new Contract(
        this.getEntry('HorizonStaking').address,
        mergeABIs(
          mergeABIs(
            loadArtifact('HorizonStaking', GraphHorizonArtifactsMap.HorizonStaking).abi,
            loadArtifact('HorizonStakingBase', GraphHorizonArtifactsMap.HorizonStaking).abi,
          ),
          loadArtifact('HorizonStakingExtension', GraphHorizonArtifactsMap.HorizonStaking).abi,
        ),
        signerOrProvider,
      )
      contracts.HorizonStaking = stakingOverride
    }

    this._assertGraphHorizonContracts(contracts)

    // Aliases
    contracts.GraphToken = contracts.L2GraphToken
    contracts.GraphTokenGateway = contracts.L2GraphTokenGateway
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
        logError(errMessage)
      }
    }
  }
}

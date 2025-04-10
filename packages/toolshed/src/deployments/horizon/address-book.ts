import { GraphHorizonArtifactsMap, GraphHorizonContractNameList } from './contracts'
import { logDebug, logError } from '../../lib/logger'
import { Provider, Signer } from 'ethers'
import { AddressBook } from '../address-book'
import { assertObject } from '../../lib/assert'
import { Contract } from 'ethers'
import { loadArtifact } from '../artifact'
import { mergeABIs } from '../../core/abi'

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
  ): GraphHorizonContracts {
    logDebug('Loading Graph Horizon contracts...')

    const contracts = this._loadContracts(
      GraphHorizonArtifactsMap,
      signerOrProvider,
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
      contracts.HorizonStaking = stakingOverride
    }

    this._assertGraphHorizonContracts(contracts)

    // Aliases
    contracts.GraphToken = contracts.L2GraphToken
    // contracts.GraphTokenGateway = contracts.L2GraphTokenGateway
    contracts.Curation = contracts.L2Curation
    if (contracts.HorizonStaking) {
      // add LegacyStaking alias using old IL2Staking abi
      // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
      contracts.LegacyStaking = new Contract(
        contracts.HorizonStaking.target,
        loadArtifact('IL2Staking', GraphHorizonArtifactsMap.LegacyStaking).abi,
        signerOrProvider,
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

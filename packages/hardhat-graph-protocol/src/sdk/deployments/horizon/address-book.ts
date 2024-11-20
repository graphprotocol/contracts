import path from 'path'

import { Contract, Provider, Signer } from 'ethers'
import { logDebug, logError, logWarn } from '../../../logger'
import { AddressBook } from '../../address-book'
import { assertObject } from '../../utils/assertion'
import { GraphHorizonContractNameList } from './types'

import type { GraphHorizonContractName, GraphHorizonContracts } from './types'

export class GraphHorizonAddressBook extends AddressBook<number, GraphHorizonContractName> {
  isValidContractName(name: string): boolean {
    return isGraphHorizonContractName(name)
  }

  loadContracts(
    chainId: number,
    signerOrProvider?: Signer | Provider,
  ): GraphHorizonContracts {
    logDebug('Loading Graph Network contracts...')
    const artifactsPath = path.resolve('node_modules', '@graphprotocol/contracts/build/contracts')

    const contracts = this._loadContracts(
      artifactsPath,
      signerOrProvider,
    )
    assertGraphHorizonContracts(contracts, chainId)

    // Iterator
    contracts[Symbol.iterator] = function* () {
      for (const key of Object.keys(this)) {
        yield this[key as GraphHorizonContractName] as Contract
      }
    }

    return contracts
  }
}

function isGraphHorizonContractName(name: unknown): name is GraphHorizonContractName {
  return (
    typeof name === 'string'
    && GraphHorizonContractNameList.includes(name as GraphHorizonContractName)
  )
}

function assertGraphHorizonContracts(
  contracts: unknown,
  chainId: number,
  strictAssert?: boolean,
): asserts contracts is GraphHorizonContracts {
  assertObject(contracts)

  // Allow loading contracts not defined in contract list but raise a warning
  const contractNames = Object.keys(contracts)
  if (!contractNames.every(c => isGraphHorizonContractName(c))) {
    logWarn(
      `Loaded unregistered GraphHorizon contract: ${contractNames.filter(
        c => !isGraphHorizonContractName(c),
      ).join()}`,
    )
  }

  // Assert that all GraphNetworkContracts were loaded
  for (const contractName of GraphHorizonContractNameList) {
    if (!contracts[contractName]) {
      const errMessage = `Missing GraphHorizon contract: ${contractName} for chainId ${chainId}`
      logError(errMessage)
      if (strictAssert) {
        throw new Error(errMessage)
      }
    }
  }
}

import { GraphNetworkContractName, isGraphNetworkContractName } from './contracts/list'
import { GraphChainId, isGraphChainId } from '../../..'
import { AddressBook } from '../../lib/address-book'

import type { AddressBookJson } from '../../lib/types/address-book'

export class GraphNetworkAddressBook extends AddressBook<GraphChainId, GraphNetworkContractName> {
  assertChainId(chainId: string | number): asserts chainId is GraphChainId {
    if (!isGraphChainId(chainId)) {
      throw new Error(`ChainId not supported: ${chainId}`)
    }
  }

  // Asserts the provided object is a valid address book
  // Logs warnings for unsupported chain ids or invalid contract names
  // TODO: should we enforce json format here and throw instead of just logging?
  assertAddressBookJson(
    json: unknown,
  ): asserts json is AddressBookJson<GraphChainId, GraphNetworkContractName> {
    this._assertAddressBookJson(json)

    // // Validate contract names
    const contractList = json[this.chainId]

    const contractNames = contractList ? Object.keys(contractList) : []
    for (const contract of contractNames) {
      if (!isGraphNetworkContractName(contract)) {
        const message = `Detected invalid GraphNetworkContract in address book: ${contract}, for chainId ${this.chainId}`
        if (this.strictAssert) {
          throw new Error(message)
        } else {
          console.error(message)
        }
      }
    }
  }
}

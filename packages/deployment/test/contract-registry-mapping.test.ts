import {
  GraphHorizonContractNameList,
  GraphIssuanceContractNameList,
  SubgraphServiceContractNameList,
} from '@graphprotocol/toolshed/deployments'
import { expect } from 'chai'

import { type AddressBookType, CONTRACT_REGISTRY, getContractsByAddressBook } from '../lib/contract-registry.js'
import { graph } from '../rocketh/deploy.js'

/**
 * Contract Registry <-> Address Book Mapping Tests
 *
 * These tests ensure that registry entries and address book types stay in sync.
 * Every registry entry for an address book should have a corresponding type in that address book,
 * and vice versa.
 *
 * This is critical because:
 * - Registry drives deployment scripts (what to deploy)
 * - Address book types enforce what can be stored (type safety)
 * - Mismatch causes runtime errors when deploying or syncing
 */

describe('Contract Registry Mapping', () => {
  describe('Issuance Address Book Mapping', () => {
    it('should have all registry issuance contracts in address book type', () => {
      // Get all issuance contracts from registry
      const registryContracts = getContractsByAddressBook('issuance').map(([name]) => name)

      // Get address book type definition
      // We'll use the getIssuanceAddressBook to access the validContracts list
      const addressBook = graph.getIssuanceAddressBook(42161) // Chain ID doesn't matter for type check

      // Every registry contract should be in address book type
      const missing: string[] = []
      for (const contractName of registryContracts) {
        if (!addressBook.isContractName(contractName)) {
          missing.push(contractName)
        }
      }

      expect(missing).to.deep.equal([], `Registry has contracts not in address book type: ${missing.join(', ')}`)
    })

    it('should have all address book issuance contracts in registry', () => {
      // Get address book type definition from toolshed
      const addressBookContracts = [...GraphIssuanceContractNameList]

      // Get all issuance contracts from registry
      const registryContracts = getContractsByAddressBook('issuance').map(([name]) => name)

      // Every address book contract should be in registry
      const missing: string[] = []
      for (const contractName of addressBookContracts) {
        if (!registryContracts.includes(contractName)) {
          missing.push(contractName)
        }
      }

      expect(missing).to.deep.equal([], `Address book has contracts not in registry: ${missing.join(', ')}`)
    })

    it('should have exact same contract sets in registry and address book', () => {
      // Get both sets
      const registryContracts = getContractsByAddressBook('issuance')
        .map(([name]) => name)
        .sort()
      const addressBookContracts = [...GraphIssuanceContractNameList].sort()

      // They should be identical
      expect(registryContracts).to.deep.equal(
        addressBookContracts,
        'Registry and address book contract lists should match exactly',
      )
    })
  })

  describe('All Address Books Mapping', () => {
    const addressBooks: Array<{
      type: AddressBookType
      contractNameList: readonly string[]
      requireBidirectional: boolean
    }> = [
      { type: 'horizon', contractNameList: GraphHorizonContractNameList, requireBidirectional: false },
      { type: 'subgraph-service', contractNameList: SubgraphServiceContractNameList, requireBidirectional: false },
      { type: 'issuance', contractNameList: GraphIssuanceContractNameList, requireBidirectional: true },
    ]

    addressBooks.forEach(({ type, contractNameList, requireBidirectional }) => {
      describe(`${type} address book`, () => {
        it('should have all registry contracts in address book type', () => {
          // Get all contracts from registry for this address book
          const registryContracts = getContractsByAddressBook(type).map(([name]) => name)

          // Get address book type definition from toolshed
          const addressBookContracts = [...contractNameList]

          // Every registry contract should be in address book type
          const missing: string[] = []
          for (const contractName of registryContracts) {
            if (!addressBookContracts.includes(contractName)) {
              missing.push(contractName)
            }
          }

          expect(missing).to.deep.equal(
            [],
            `${type} registry has contracts not in address book type: ${missing.join(', ')}`,
          )
        })

        if (requireBidirectional) {
          it('should have all address book contracts in registry', () => {
            // Get address book type definition from toolshed
            const addressBookContracts = [...contractNameList]

            // Get all contracts from registry for this address book
            const registryContracts = getContractsByAddressBook(type).map(([name]) => name)

            // Every address book contract should be in registry
            const missing: string[] = []
            for (const contractName of addressBookContracts) {
              if (!registryContracts.includes(contractName)) {
                missing.push(contractName)
              }
            }

            expect(missing).to.deep.equal(
              [],
              `${type} address book has contracts not in registry: ${missing.join(', ')}`,
            )
          })

          it('should have exact same contract sets', () => {
            // Get both sets
            const registryContracts = getContractsByAddressBook(type)
              .map(([name]) => name)
              .sort()
            const addressBookContracts = [...contractNameList].sort()

            // They should be identical
            expect(registryContracts).to.deep.equal(
              addressBookContracts,
              `${type}: Registry and address book contract lists should match exactly`,
            )
          })
        }
      })
    })
  })

  describe('Registry Structure', () => {
    it('should have valid namespace structure', () => {
      const validAddressBooks: AddressBookType[] = ['horizon', 'subgraph-service', 'issuance']

      // Registry should be namespaced by address book type
      for (const key of Object.keys(CONTRACT_REGISTRY)) {
        expect(validAddressBooks).to.include(key, `Invalid namespace key: ${key}`)
      }

      // Each namespace should contain contract metadata
      for (const [addressBook, contracts] of Object.entries(CONTRACT_REGISTRY)) {
        expect(contracts).to.be.an('object', `${addressBook} should contain contract metadata`)
        expect(Object.keys(contracts).length).to.be.greaterThan(0, `${addressBook} should have at least one contract`)
      }
    })

    it('should have valid addressBook values', () => {
      const validAddressBooks: AddressBookType[] = ['horizon', 'subgraph-service', 'issuance']

      // Verify all namespace keys are valid address book types
      for (const namespace of Object.keys(CONTRACT_REGISTRY)) {
        expect(validAddressBooks).to.include(namespace, `Invalid addressBook namespace: ${namespace}`)
      }
    })
  })
})

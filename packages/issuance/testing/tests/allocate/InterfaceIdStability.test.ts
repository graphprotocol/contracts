// Use dynamic import for ESM/CJS interop
import { expect } from 'chai'

// Module-level variables for lazy-loaded factories
let factories: {
  IIssuanceAllocationAdministration__factory: any
  IIssuanceAllocationData__factory: any
  IIssuanceAllocationDistribution__factory: any
  IIssuanceAllocationStatus__factory: any
  IIssuanceTarget__factory: any
  ISendTokens__factory: any
}

/**
 * Allocate Interface ID Stability Tests
 *
 * These tests verify that allocate-specific interface IDs remain stable across builds.
 * Changes to these IDs indicate breaking changes to the interface definitions.
 *
 * If a test fails:
 * 1. Verify the interface change was intentional
 * 2. Understand the impact on deployed contracts
 * 3. Update the expected ID if the change is correct
 * 4. Document the breaking change in release notes
 */
describe('Allocate Interface ID Stability', () => {
  before(async () => {
    // Import directly from dist to avoid ts-node circular dependency issues
    const interfacesTypes = await import('@graphprotocol/interfaces/dist/types/index.js')
    factories = {
      IIssuanceAllocationAdministration__factory: interfacesTypes.IIssuanceAllocationAdministration__factory,
      IIssuanceAllocationData__factory: interfacesTypes.IIssuanceAllocationData__factory,
      IIssuanceAllocationDistribution__factory: interfacesTypes.IIssuanceAllocationDistribution__factory,
      IIssuanceAllocationStatus__factory: interfacesTypes.IIssuanceAllocationStatus__factory,
      IIssuanceTarget__factory: interfacesTypes.IIssuanceTarget__factory,
      ISendTokens__factory: interfacesTypes.ISendTokens__factory,
    }
  })

  it('IIssuanceAllocationDistribution should have stable interface ID', () => {
    expect(factories.IIssuanceAllocationDistribution__factory.interfaceId).to.equal('0x79da37fc')
  })

  it('IIssuanceAllocationAdministration should have stable interface ID', () => {
    expect(factories.IIssuanceAllocationAdministration__factory.interfaceId).to.equal('0x50d8541d')
  })

  it('IIssuanceAllocationStatus should have stable interface ID', () => {
    expect(factories.IIssuanceAllocationStatus__factory.interfaceId).to.equal('0xa896602d')
  })

  it('IIssuanceAllocationData should have stable interface ID', () => {
    expect(factories.IIssuanceAllocationData__factory.interfaceId).to.equal('0x48c3c62e')
  })

  it('IIssuanceTarget should have stable interface ID', () => {
    expect(factories.IIssuanceTarget__factory.interfaceId).to.equal('0xaee4dc43')
  })

  it('ISendTokens should have stable interface ID', () => {
    expect(factories.ISendTokens__factory.interfaceId).to.equal('0x05ab421d')
  })
})

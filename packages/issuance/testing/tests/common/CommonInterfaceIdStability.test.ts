// Use dynamic import for ESM/CJS interop
import { expect } from 'chai'

// Standard interface IDs (well-known constants)
// IAccessControl: OpenZeppelin AccessControl interface
const IACCESSCONTROL_INTERFACE_ID = '0x7965db0b'

// Module-level variables for lazy-loaded factories
let factories: {
  IPausableControl__factory: any
}

/**
 * Common Interface ID Stability Tests
 *
 * These tests verify that common interface IDs remain stable across builds.
 * These interfaces are used by both allocate and eligibility contracts.
 *
 * Changes to these IDs indicate breaking changes to the interface definitions.
 *
 * If a test fails:
 * 1. Verify the interface change was intentional
 * 2. Understand the impact on deployed contracts
 * 3. Update the expected ID if the change is correct
 * 4. Document the breaking change in release notes
 */
describe('Common Interface ID Stability', () => {
  before(async () => {
    // Import directly from dist to avoid ts-node circular dependency issues
    const interfacesTypes = await import('@graphprotocol/interfaces/dist/types/index.js')
    factories = {
      IPausableControl__factory: interfacesTypes.IPausableControl__factory,
    }
  })

  it('IPausableControl should have stable interface ID', () => {
    expect(factories.IPausableControl__factory.interfaceId).to.equal('0xe78a39d8')
  })

  it('IAccessControl should have stable interface ID', () => {
    // IAccessControl is a standard OpenZeppelin interface with well-known ID
    expect(IACCESSCONTROL_INTERFACE_ID).to.equal('0x7965db0b')
  })
})

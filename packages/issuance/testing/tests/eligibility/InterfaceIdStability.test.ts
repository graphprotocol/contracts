// Use dynamic import for ESM/CJS interop
import { expect } from 'chai'

// Module-level variables for lazy-loaded factories
let factories: {
  IRewardsEligibility__factory: any
  IRewardsEligibilityAdministration__factory: any
  IRewardsEligibilityReporting__factory: any
  IRewardsEligibilityStatus__factory: any
}

/**
 * Eligibility Interface ID Stability Tests
 *
 * These tests verify that eligibility-specific interface IDs remain stable across builds.
 * Changes to these IDs indicate breaking changes to the interface definitions.
 *
 * If a test fails:
 * 1. Verify the interface change was intentional
 * 2. Understand the impact on deployed contracts
 * 3. Update the expected ID if the change is correct
 * 4. Document the breaking change in release notes
 *
 * Note: Common interfaces (IPausableControl, IAccessControl) are tested in
 * CommonInterfaceIdStability.test.ts at the root level.
 */
describe('Eligibility Interface ID Stability', () => {
  before(async () => {
    // Import directly from dist to avoid ts-node circular dependency issues
    const interfacesTypes = await import('@graphprotocol/interfaces/dist/types/index.js')
    factories = {
      IRewardsEligibility__factory: interfacesTypes.IRewardsEligibility__factory,
      IRewardsEligibilityAdministration__factory: interfacesTypes.IRewardsEligibilityAdministration__factory,
      IRewardsEligibilityReporting__factory: interfacesTypes.IRewardsEligibilityReporting__factory,
      IRewardsEligibilityStatus__factory: interfacesTypes.IRewardsEligibilityStatus__factory,
    }
  })

  it('IRewardsEligibility should have stable interface ID', () => {
    expect(factories.IRewardsEligibility__factory.interfaceId).to.equal('0x66e305fd')
  })

  it('IRewardsEligibilityAdministration should have stable interface ID', () => {
    expect(factories.IRewardsEligibilityAdministration__factory.interfaceId).to.equal('0x9a69f6aa')
  })

  it('IRewardsEligibilityReporting should have stable interface ID', () => {
    expect(factories.IRewardsEligibilityReporting__factory.interfaceId).to.equal('0x38b7c077')
  })

  it('IRewardsEligibilityStatus should have stable interface ID', () => {
    expect(factories.IRewardsEligibilityStatus__factory.interfaceId).to.equal('0x53740f19')
  })
})

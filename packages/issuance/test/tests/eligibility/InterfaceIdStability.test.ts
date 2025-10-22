import {
  IRewardsEligibility__factory,
  IRewardsEligibilityAdministration__factory,
  IRewardsEligibilityReporting__factory,
  IRewardsEligibilityStatus__factory,
} from '@graphprotocol/interfaces/types'
import { expect } from 'chai'

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
  it('IRewardsEligibility should have stable interface ID', () => {
    expect(IRewardsEligibility__factory.interfaceId).to.equal('0x66e305fd')
  })

  it('IRewardsEligibilityAdministration should have stable interface ID', () => {
    expect(IRewardsEligibilityAdministration__factory.interfaceId).to.equal('0x9a69f6aa')
  })

  it('IRewardsEligibilityReporting should have stable interface ID', () => {
    expect(IRewardsEligibilityReporting__factory.interfaceId).to.equal('0x38b7c077')
  })

  it('IRewardsEligibilityStatus should have stable interface ID', () => {
    expect(IRewardsEligibilityStatus__factory.interfaceId).to.equal('0x53740f19')
  })
})

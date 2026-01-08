import { IPausableControl__factory } from '@graphprotocol/interfaces/types'
import { IAccessControl__factory } from '@graphprotocol/issuance/types'
import { expect } from 'chai'

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
  it('IPausableControl should have stable interface ID', () => {
    expect(IPausableControl__factory.interfaceId).to.equal('0xe78a39d8')
  })

  it('IAccessControl should have stable interface ID', () => {
    expect(IAccessControl__factory.interfaceId).to.equal('0x7965db0b')
  })
})

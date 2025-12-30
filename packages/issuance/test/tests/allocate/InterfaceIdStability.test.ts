import {
  IIssuanceAllocationAdministration__factory,
  IIssuanceAllocationData__factory,
  IIssuanceAllocationDistribution__factory,
  IIssuanceAllocationStatus__factory,
  IIssuanceTarget__factory,
  ISendTokens__factory,
} from '@graphprotocol/interfaces/types'
import { expect } from 'chai'

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
  it('IIssuanceAllocationDistribution should have stable interface ID', () => {
    expect(IIssuanceAllocationDistribution__factory.interfaceId).to.equal('0x79da37fc')
  })

  it('IIssuanceAllocationAdministration should have stable interface ID', () => {
    expect(IIssuanceAllocationAdministration__factory.interfaceId).to.equal('0x50d8541d')
  })

  it('IIssuanceAllocationStatus should have stable interface ID', () => {
    expect(IIssuanceAllocationStatus__factory.interfaceId).to.equal('0xa896602d')
  })

  it('IIssuanceAllocationData should have stable interface ID', () => {
    expect(IIssuanceAllocationData__factory.interfaceId).to.equal('0x48c3c62e')
  })

  it('IIssuanceTarget should have stable interface ID', () => {
    expect(IIssuanceTarget__factory.interfaceId).to.equal('0xaee4dc43')
  })

  it('ISendTokens should have stable interface ID', () => {
    expect(ISendTokens__factory.interfaceId).to.equal('0x05ab421d')
  })
})

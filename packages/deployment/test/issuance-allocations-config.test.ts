import { expect } from 'chai'
import { parseUnits } from 'viem'

import { ALLOCATION_TARGET_CONTRACTS, allocationTargetContract } from '../lib/contract-registry.js'
import { getResolvedSettings, type ResolvedSettings, validateIssuanceAllocations } from '../lib/deployment-config.js'

/**
 * Issuance allocation config: generic per-target table validated against RM's
 * on-chain issuancePerBlock. Tests cover the resolver and the validation rules
 * (config total vs RM, sum vs total) — the mechanism, not per-network values.
 */
describe('Issuance allocation config', () => {
  describe('allocationTargetContract', () => {
    it('resolves RewardsManager from the horizon address book', () => {
      const entry = allocationTargetContract('RewardsManager')
      expect(entry.name).to.equal('RewardsManager')
      expect(entry.addressBook).to.equal('horizon')
    })

    it('resolves RecurringAgreementManager from the issuance address book', () => {
      const entry = allocationTargetContract('RecurringAgreementManager')
      expect(entry.name).to.equal('RecurringAgreementManager')
      expect(entry.addressBook).to.equal('issuance')
    })

    it('lists the currently-allocatable targets', () => {
      expect([...ALLOCATION_TARGET_CONTRACTS]).to.deep.equal(['RewardsManager', 'RecurringAgreementManager'])
    })
  })

  describe('getResolvedSettings', () => {
    it('resolves an empty allocation table for an unknown chain', () => {
      const s = getResolvedSettings(999999)
      expect(s.issuanceAllocator.allocations).to.deep.equal([])
      expect(s.issuanceAllocator.issuancePerBlock).to.equal(undefined)
    })

    it('only resolves valid target names for known chains', () => {
      for (const chainId of [42161, 421614, 1337]) {
        const s = getResolvedSettings(chainId)
        for (const a of s.issuanceAllocator.allocations) {
          expect(ALLOCATION_TARGET_CONTRACTS as readonly string[]).to.include(a.target)
        }
      }
    })
  })

  describe('validateIssuanceAllocations', () => {
    const make = (
      issuancePerBlock: string | undefined,
      allocations: ResolvedSettings['issuanceAllocator']['allocations'],
    ): ResolvedSettings => ({
      rewardsManager: { revertOnIneligible: true },
      recurringAgreementManager: {},
      issuanceAllocator: { issuancePerBlock, allocations },
      recurringCollector: { revokeSignerThawingPeriod: '0', eip712Name: 'x', eip712Version: '1' },
    })

    const rm = parseUnits('6.0365', 18)
    const fullTable: ResolvedSettings['issuanceAllocator']['allocations'] = [
      { target: 'RewardsManager', allocatorGrtPerBlock: '0', selfGrtPerBlock: '5.5365' },
      { target: 'RecurringAgreementManager', allocatorGrtPerBlock: '0.5', selfGrtPerBlock: '0' },
    ]

    it('returns [] when no allocations are configured', () => {
      expect(validateIssuanceAllocations(make(undefined, []), rm)).to.deep.equal([])
    })

    it('errors when allocations are present but issuancePerBlock is not declared', () => {
      expect(() => validateIssuanceAllocations(make(undefined, fullTable), rm)).to.throw(/issuancePerBlock is not/)
    })

    it('errors when the declared total differs from RM on-chain', () => {
      expect(() => validateIssuanceAllocations(make('6.0365', fullTable), parseUnits('7', 18))).to.throw(
        /does not match RM/,
      )
    })

    it('errors when the allocations do not sum to the declared total', () => {
      const short = [
        { target: 'RewardsManager' as const, allocatorGrtPerBlock: '0', selfGrtPerBlock: '5' },
        { target: 'RecurringAgreementManager' as const, allocatorGrtPerBlock: '0.5', selfGrtPerBlock: '0' },
      ]
      expect(() => validateIssuanceAllocations(make('6.0365', short), rm)).to.throw(/must allocate exactly/)
    })

    it('returns parsed wei rates when the table is valid and balanced', () => {
      const result = validateIssuanceAllocations(make('6.0365', fullTable), rm)
      expect(result).to.deep.equal([
        { target: 'RewardsManager', allocatorMintingRate: 0n, selfMintingRate: parseUnits('5.5365', 18) },
        { target: 'RecurringAgreementManager', allocatorMintingRate: parseUnits('0.5', 18), selfMintingRate: 0n },
      ])
    })
  })
})

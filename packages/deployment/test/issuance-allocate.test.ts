import { expect } from 'chai'
import { parseUnits } from 'viem'

import { compareAllocationDelta, isSkippableUndeployedTarget } from '../lib/issuance-allocate.js'

/**
 * Decrease-first ordering of the pending `setTargetAllocation` calls.
 *
 * `IssuanceAllocator` enforces that the explicit targets never sum above
 * `issuancePerBlock` — the default target absorbs the slack and cannot go negative.
 * If an increase were emitted before the matching decrease, the batch would
 * transiently overshoot and revert mid-way, after earlier calls had already moved
 * issuance. This is the single most consequential property of the shared allocate
 * logic, so it is pinned here rather than resting on a fork rehearsal.
 */
describe('issuance-allocate — decrease-first ordering', () => {
  const grt = (v: string) => parseUnits(v, 18)

  const sortLabels = (pending: { label: string; delta: bigint }[]): string[] =>
    [...pending].sort(compareAllocationDelta).map((p) => p.label)

  it('emits the decrease before the increase (GIP-0089 mainnet split)', () => {
    // Input order is config order: RewardsManager first, InnovationAllocation second.
    const pending = [
      { label: 'RewardsManager', delta: -grt('24.146') },
      { label: 'InnovationAllocation', delta: grt('24.146') },
    ]
    expect(sortLabels(pending)).to.deep.equal(['RewardsManager', 'InnovationAllocation'])
  })

  it('emits the decrease first even when the increase is listed first', () => {
    const pending = [
      { label: 'InnovationAllocation', delta: grt('24.146') },
      { label: 'RewardsManager', delta: -grt('24.146') },
    ]
    expect(sortLabels(pending)).to.deep.equal(['RewardsManager', 'InnovationAllocation'])
  })

  it('places every decrease ahead of every increase, and zero-delta entries between', () => {
    const pending = [
      { label: 'increase-small', delta: grt('1') },
      { label: 'decrease-small', delta: -grt('1') },
      { label: 'unchanged', delta: 0n },
      { label: 'increase-big', delta: grt('50') },
      { label: 'decrease-big', delta: -grt('50') },
    ]
    expect(sortLabels(pending)).to.deep.equal([
      'decrease-big',
      'decrease-small',
      'unchanged',
      'increase-small',
      'increase-big',
    ])
  })

  it('is a total order on bigint deltas (no Number coercion overflow)', () => {
    // Deltas are wei-scale bigints; a comparator returning a-b as a Number would
    // overflow or lose precision. Two values that differ only in the low wei.
    const a = { label: 'a', delta: grt('24.146') }
    const b = { label: 'b', delta: grt('24.146') + 1n }
    expect(compareAllocationDelta(a, b)).to.equal(-1)
    expect(compareAllocationDelta(b, a)).to.equal(1)
    expect(compareAllocationDelta(a, { label: 'a2', delta: a.delta })).to.equal(0)
  })
})

/**
 * Refusal to emit a partial batch when a configured target is not deployed.
 *
 * `validateIssuanceAllocations` proves the table sums to RM's on-chain
 * `issuancePerBlock` before the loop runs. Skipping a nonzero row from that proven
 * table emits calls that free issuance the missing target cannot claim, so it falls
 * to the IssuanceAllocator default target — a silent 20% cut to indexer rewards on
 * mainnet, with no revert to catch it. A zero-rate entry contributes nothing to the
 * total and stays skippable.
 *
 * Only the nonzero-vs-zero decision is unit-testable here; the surrounding refusal
 * needs a rocketh Environment, and is exercised end-to-end against Arbitrum One in
 * the runbook verification.
 */
describe('issuance-allocate — undeployed target skippability', () => {
  const grt = (v: string) => parseUnits(v, 18)

  it('does not skip a target configured at a nonzero allocator rate', () => {
    expect(isSkippableUndeployedTarget({ allocatorMintingRate: grt('24.146'), selfMintingRate: 0n })).to.equal(false)
  })

  it('does not skip a target configured at a nonzero self-minting rate', () => {
    expect(isSkippableUndeployedTarget({ allocatorMintingRate: 0n, selfMintingRate: grt('96.584') })).to.equal(false)
  })

  it('does not skip a target whose rates are nonzero only in sum', () => {
    expect(isSkippableUndeployedTarget({ allocatorMintingRate: 1n, selfMintingRate: 1n })).to.equal(false)
  })

  it('skips a target configured at zero (RecurringAgreementManager on Sepolia)', () => {
    expect(isSkippableUndeployedTarget({ allocatorMintingRate: 0n, selfMintingRate: 0n })).to.equal(true)
  })
})

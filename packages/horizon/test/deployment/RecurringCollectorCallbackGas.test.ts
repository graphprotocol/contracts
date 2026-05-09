import { expect } from 'chai'
import hre from 'hardhat'
import { ethers } from 'hardhat'

/**
 * Boundary checks for `CALLBACK_GAS_OVERHEAD` in `RecurringCollector`.
 *
 * Foundry/REVM in this project does not differentiate cold/warm account access in
 * `gasleft()`-derived measurements (verified empirically: `vm.cool` produces no gas
 * differential, and a fresh-deployed contract's first staticcall costs the same as a
 * subsequent one). Both directions — cold δ on the eligibility staticcall, warm δ on
 * the after-collection CALL — therefore need a Hardhat-side test against an EIP-2929-
 * applying EVM. Each `it(...)` block here covers one direction.
 *
 * The horizon Foundry tests retain the *negative* boundary
 * (`test_Collect_Revert_WhenInsufficientCallbackGas*` in `afterCollection.t.sol`):
 * `gasleft < threshold` reverts with `InsufficientCallbackGas`. Those exercises don't
 * depend on cold/warm differentiation. The *positive* boundary — at lowest passing gas,
 * the forwarded gas is within tolerance of MAX — does, and lives here.
 */
describe('RecurringCollector callback gas overhead', () => {
  const MAX_PAYER_CALLBACK_GAS = 1_500_000n
  const TOLERANCE = 500n

  /**
   * Each `await probe.probeEligibility(...)` is a fresh ethers transaction, so each one
   * starts with an empty access list — the first access to `payer` inside the call genuinely
   * incurs the cold-access cost on Hardhat Network's EVM (which does apply EIP-2929).
   *
   * Discriminator at the boundary:
   *   - `CallbackGasProbeInsufficientCallbackGas` at `hi - 1` → precheck is the gate, OVERHEAD
   *     covers cold δ.
   *   - `CallbackGasProbeNotEligible` at `hi - 1` → precheck passed but forwarded gas was
   *     below `MAX − tolerance`, i.e. OVERHEAD < cold δ.
   *
   * **If this test fails with `NotEligible`**, `CALLBACK_GAS_OVERHEAD` no longer covers the
   * cold-access cost. Action: bump it in `RecurringCollector.sol` (and mirror in
   * `CallbackGasProbe.sol`); do not raise `tolerance` here.
   */
  it('CALLBACK_GAS_OVERHEAD covers cold-access cost on the eligibility staticcall', async () => {
    // Deploy the probe and a gasleft-reporting eligibility mock. The mock returns
    // false from isEligible() if forwarded gas dropped below MAX_PAYER_CALLBACK_GAS - TOLERANCE.
    const ProbeFactory = await ethers.getContractFactory('CallbackGasProbe')
    const probe = await ProbeFactory.deploy()
    await probe.waitForDeployment()

    const MockFactory = await ethers.getContractFactory('GasReportingEligibilityMock')
    const mock = await MockFactory.deploy(MAX_PAYER_CALLBACK_GAS - TOLERANCE)
    await mock.waitForDeployment()

    const provider = ethers.Wallet.createRandom().address

    const callBoundary = async (gasLimit: bigint): Promise<{ ok: boolean; reason: string }> => {
      try {
        // staticCall lets us probe a view function without sending a real transaction —
        // but we still need a fresh-tx access list so the payer is cold. Hardhat treats
        // each staticCall as its own eth_call invocation with a fresh access list.
        await probe.probeEligibility.staticCall(await mock.getAddress(), provider, { gasLimit })
        return { ok: true, reason: 'success' }
      } catch (e: any) {
        // ethers v6 throws errors with `data` (revert payload) and a parsed `errorName`.
        const data: string = e?.data ?? e?.info?.error?.data ?? ''
        if (typeof data === 'string' && data.startsWith('0x')) {
          const insufficientCallbackGasSel = probe.interface.getError(
            'CallbackGasProbeInsufficientCallbackGas',
          )!.selector
          const notEligibleSel = probe.interface.getError('CallbackGasProbeNotEligible')!.selector
          if (data.startsWith(insufficientCallbackGasSel)) return { ok: false, reason: 'InsufficientCallbackGas' }
          if (data.startsWith(notEligibleSel)) return { ok: false, reason: 'NotEligible' }
        }
        // Out-of-gas at the EVM-level (rather than a logic revert) shows up here too —
        // treat as "below precheck threshold".
        return { ok: false, reason: 'oog-or-other' }
      }
    }

    // Binary search the lowest gas at which probe succeeds.
    let lo = 1_500_000n
    let hi = 2_000_000n
    while (hi - lo > 1n) {
      const mid = (lo + hi) / 2n
      const { ok } = await callBoundary(mid)
      if (ok) hi = mid
      else lo = mid
    }

    // Sanity: succeeds at hi.
    const success = await callBoundary(hi)
    expect(success.ok, 'binary search settled on a gas value where probe should succeed').to.be.true

    // Discriminator: at hi - 1 the revert reason must be InsufficientCallbackGas (precheck
    // is the gate), not NotEligible (forwarded gas dropped below MAX - tolerance).
    const failure = await callBoundary(hi - 1n)
    expect(failure.ok, 'expected revert at hi - 1').to.be.false
    expect(
      failure.reason,
      `boundary revert at hi-1 was ${failure.reason}, expected InsufficientCallbackGas — CALLBACK_GAS_OVERHEAD does not cover cold delta`,
    ).to.equal('InsufficientCallbackGas')
  })

  /**
   * Warm-path counterpart: the after-collection CALL in `_postCollectCallback`. The probe
   * first warms `payer` via a staticcall (mirroring the eligibility site that runs ahead
   * of the after-callback in `_collect`), then does the precheck + CALL pattern.
   *
   * At the lowest outer gas at which the precheck just clears, EIP-150's `gasleft * 63/64`
   * cap is at its tightest — the forwarded gas is `MAX − δ_warm`, where δ_warm is the
   * pre-CALL Solidity overhead between `gasleft()` and the CALL opcode plus the warm CALL
   * fixed cost. Asserting `received >= MAX − tolerance` verifies that
   * `CALLBACK_GAS_OVERHEAD ≥ δ_warm` at the production configuration.
   *
   * **If this test fails** look at *what changed*:
   *   - You added pre-CALL Solidity overhead (extra arg encoding, an SLOAD before the
   *     assembly block, code between `gasleft()` and CALL).
   *     Action: bump `CALLBACK_GAS_OVERHEAD` in `RecurringCollector.sol` (and mirror in
   *     `CallbackGasProbe.sol`); **don't** just raise `TOLERANCE` here.
   *   - You changed `MAX_PAYER_CALLBACK_GAS`. Update `MAX_PAYER_CALLBACK_GAS` here to follow.
   */
  it('CALLBACK_GAS_OVERHEAD covers warm-path δ on the after-collection CALL', async () => {
    const ProbeFactory = await ethers.getContractFactory('CallbackGasProbe')
    const probe = await ProbeFactory.deploy()
    await probe.waitForDeployment()

    const MockFactory = await ethers.getContractFactory('AfterCollectionGasReportingMock')
    const mock = await MockFactory.deploy()
    await mock.waitForDeployment()

    type Outcome = { ok: true; received: bigint } | { ok: false; reason: string }

    const callBoundary = async (gasLimit: bigint): Promise<Outcome> => {
      try {
        const received = await probe.probeAfterCollection.staticCall(await mock.getAddress(), { gasLimit })
        return { ok: true, received: BigInt(received) }
      } catch (e: any) {
        const data: string = e?.data ?? e?.info?.error?.data ?? ''
        if (typeof data === 'string' && data.startsWith('0x')) {
          const insufficientSel = probe.interface.getError('CallbackGasProbeInsufficientCallbackGas')!.selector
          const failedSel = probe.interface.getError('CallbackGasProbeAfterCollectionFailed')!.selector
          if (data.startsWith(insufficientSel)) return { ok: false, reason: 'InsufficientCallbackGas' }
          if (data.startsWith(failedSel)) return { ok: false, reason: 'AfterCollectionFailed' }
        }
        return { ok: false, reason: 'oog-or-other' }
      }
    }

    // Binary search the lowest gas at which the probe succeeds.
    let lo = 1_500_000n
    let hi = 2_000_000n
    while (hi - lo > 1n) {
      const mid = (lo + hi) / 2n
      const result = await callBoundary(mid)
      if (result.ok) hi = mid
      else lo = mid
    }

    // Re-run at the lowest passing gas; this is where the precheck is just satisfied so the
    // EIP-150 cap is tightest. The callee's recorded gasleft must stay within tolerance of MAX.
    const settled = await callBoundary(hi)
    expect(settled.ok, 'binary search settled on a gas value where probe should succeed').to.be.true
    if (!settled.ok) return // narrowing for TS

    expect(
      settled.received,
      `afterCollection received ${settled.received} < MAX_PAYER_CALLBACK_GAS - TOLERANCE (${
        MAX_PAYER_CALLBACK_GAS - TOLERANCE
      }) at boundary gas: CALLBACK_GAS_OVERHEAD margin eroded`,
    ).to.be.gte(MAX_PAYER_CALLBACK_GAS - TOLERANCE)
  })
})

// Suppress lint about unused hre import; some hardhat plugins require it for side effects.
void hre

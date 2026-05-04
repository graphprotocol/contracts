import { expect } from 'chai'
import hre from 'hardhat'
import { ethers } from 'hardhat'

/**
 * Cold-path boundary check for `CALLBACK_GAS_OVERHEAD` in `RecurringCollector`.
 *
 * Foundry/REVM in this project does not differentiate cold/warm account access in
 * `gasleft()`-derived measurements (verified empirically: `vm.cool` produces no gas
 * differential, and a fresh-deployed contract's first staticcall costs the same as a
 * subsequent one). The Foundry warm-path test
 * (`test_Collect_Callbacks_ReceiveMaxPayerCallbackGas` in `afterCollection.t.sol`) bounds
 * the warm δ; this Hardhat-side test exercises the cold δ that `CALLBACK_GAS_OVERHEAD`
 * was actually sized for (EIP-2929 cold-account access ≈ 2_600 gas).
 *
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
describe('RecurringCollector callback gas overhead (cold path)', () => {
  const MAX_PAYER_CALLBACK_GAS = 1_500_000n
  const TOLERANCE = 500n

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
})

// Suppress lint about unused hre import; some hardhat plugins require it for side effects.
void hre

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";

/**
 * @title CallbackGasProbe
 * @author Edge & Node
 * @notice Test-only contract that replicates the precheck + STATICCALL/CALL patterns used by
 * `RecurringCollector._preCollectCallbacks` (eligibility, cold path) and
 * `RecurringCollector._postCollectCallback` (afterCollection, warm path). Exists so that
 * Hardhat-side tests can verify, on a real EIP-2929-applying EVM (foundry's REVM in this
 * project does not differentiate cold/warm in `gasleft()`-derived measurements), that
 * `CALLBACK_GAS_OVERHEAD` covers both the cold-account access cost on the staticcall and the
 * warm-call dispatch overhead on the after-collection CALL.
 *
 * @dev MUST be kept in sync with the equivalent blocks in `RecurringCollector.sol`. If the
 * production constants (`MAX_PAYER_CALLBACK_GAS`, `CALLBACK_GAS_OVERHEAD`) or the precheck /
 * staticcall / call sequence change, mirror the change here. This probe is not deployed to any
 * production network.
 */
contract CallbackGasProbe {
    uint256 internal constant MAX_PAYER_CALLBACK_GAS = 1_500_000;
    uint256 internal constant CALLBACK_GAS_OVERHEAD = 3_000;

    error CallbackGasProbeInsufficientCallbackGas();
    error CallbackGasProbeNotEligible();
    error CallbackGasProbeAfterCollectionFailed();

    /**
     * @notice Re-runs the eligibility precheck + STATICCALL exactly as
     * `RecurringCollector._preCollectCallbacks` does, against `payer`. Reverts with
     * `CallbackGasProbeInsufficientCallbackGas` if the precheck blocks, or
     * `CallbackGasProbeNotEligible` if the staticcall returned an explicit `false` (i.e.
     * the forwarded gas was below whatever the payer mock requires). Used by the
     * boundary test to discriminate "precheck is the gate" (overhead healthy) from
     * "precheck passed but forwarded < threshold" (overhead insufficient for cold δ).
     * @param payer The contract to staticcall for eligibility.
     * @param provider The provider address passed through to `isEligible`.
     */
    function probeEligibility(address payer, address provider) external view {
        if (gasleft() < (MAX_PAYER_CALLBACK_GAS * 64) / 63 + CALLBACK_GAS_OVERHEAD) {
            revert CallbackGasProbeInsufficientCallbackGas();
        }
        bytes memory cd = abi.encodeCall(IProviderEligibility.isEligible, (provider));
        bool success;
        uint256 returnLen;
        uint256 result;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            success := staticcall(MAX_PAYER_CALLBACK_GAS, payer, add(cd, 0x20), mload(cd), 0x00, 0x20)
            returnLen := returndatasize()
            result := mload(0x00)
        }
        if (success && !(returnLen < 32) && result == 0) {
            revert CallbackGasProbeNotEligible();
        }
    }

    /**
     * @notice Re-runs the after-collection precheck + CALL exactly as
     * `RecurringCollector._postCollectCallback` does, against `payer`. Warms the payer first
     * (mirroring the eligibility staticcall site that runs ahead of the after-callback in
     * `_collect`) so the CALL itself measures warm-path δ.
     *
     * Returns the `gasleft()` the callee observed at function entry, captured from the
     * callee's 32-byte return word. Boundary tests use this to assert that, at the lowest
     * outer gas at which the precheck just clears, the forwarded gas stays within tolerance
     * of `MAX_PAYER_CALLBACK_GAS` — i.e. `CALLBACK_GAS_OVERHEAD ≥ δ_warm`. Reverts with
     * `CallbackGasProbeInsufficientCallbackGas` if the precheck blocks, or
     * `CallbackGasProbeAfterCollectionFailed` if the CALL itself fails.
     *
     * @dev Diverges from production in exactly one respect: it reads back the callee's
     * returndata so the test can observe the warm-path forwarded-gas value. Production
     * dispatch in `_postCollectCallback` discards returndata via `call(..., 0, 0)`. The
     * gas accounting up to and through the CALL opcode is identical.
     * @param payer The contract whose `afterCollection` should be invoked.
     * @return received The `gasleft()` value the callee saw at function entry.
     */
    function probeAfterCollection(address payer) external returns (uint256 received) {
        // Warm payer's account access list. In production, `_preCollectCallbacks` is the
        // first to touch `payer` (eligibility staticcall), so by the time
        // `_postCollectCallback` issues its CALL the account is warm. Replicate that here
        // with a staticcall whose return value we don't care about.
        bytes memory eligCd = abi.encodeCall(IProviderEligibility.isEligible, (address(0)));
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Output buffer is irrelevant — we ignore the result; this exists only to warm payer.
            pop(staticcall(MAX_PAYER_CALLBACK_GAS, payer, add(eligCd, 0x20), mload(eligCd), 0, 0))
        }

        // Precheck — same expression as `_postCollectCallback`.
        if (gasleft() < (MAX_PAYER_CALLBACK_GAS * 64) / 63 + CALLBACK_GAS_OVERHEAD) {
            revert CallbackGasProbeInsufficientCallbackGas();
        }

        // CALL afterCollection — same opcode and gas limit as `_postCollectCallback`.
        bytes memory cd = abi.encodeCall(IAgreementOwner.afterCollection, (bytes16(0), 0));
        bool ok;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ok := call(MAX_PAYER_CALLBACK_GAS, payer, 0, add(cd, 0x20), mload(cd), 0, 0)
        }
        if (!ok) revert CallbackGasProbeAfterCollectionFailed();

        // Capture the 32-byte gasleft value the callee returned. Note RC discards returndata
        // here (call(..., 0, 0)); we read it back only so the test can assert on it.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            returndatacopy(0, 0, 32)
            received := mload(0)
        }
    }
}

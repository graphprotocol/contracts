// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";

/**
 * @title CallbackGasProbe
 * @author Edge & Node
 * @notice Test-only contract that replicates the precheck + STATICCALL pattern used by
 * `RecurringCollector._preCollectCallbacks` for the eligibility path. Exists so that
 * Hardhat-side tests can verify, on a real EIP-2929-applying EVM (foundry's REVM in this
 * project does not differentiate cold/warm in `gasleft()`-derived measurements), that
 * `CALLBACK_GAS_OVERHEAD` covers the cold-account access cost on the staticcall.
 *
 * @dev MUST be kept in sync with the equivalent block in `RecurringCollector.sol`. If the
 * production constants (`MAX_PAYER_CALLBACK_GAS`, `CALLBACK_GAS_OVERHEAD`) or the precheck /
 * staticcall sequence change, mirror the change here. This probe is not deployed to any
 * production network.
 */
contract CallbackGasProbe {
    uint256 internal constant MAX_PAYER_CALLBACK_GAS = 1_500_000;
    uint256 internal constant CALLBACK_GAS_OVERHEAD = 3_000;

    error CallbackGasProbeInsufficientCallbackGas();
    error CallbackGasProbeNotEligible();

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
}

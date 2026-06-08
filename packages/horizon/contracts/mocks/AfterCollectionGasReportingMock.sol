// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable no-unused-vars

pragma solidity ^0.8.27;

/**
 * @title AfterCollectionGasReportingMock
 * @author Edge & Node
 * @notice Test-only mock used by the warm-path `CallbackGasProbe` boundary test. Returns
 * `gasleft()` from `afterCollection` so the probe can read back the forwarded-gas value via
 * returndata, and provides a no-op `isEligible` for the warm-up staticcall.
 *
 * @dev `afterCollection` shares its selector with `IAgreementOwner.afterCollection` but
 * intentionally diverges on return type (returns `uint256` so the probe can decode the
 * gasleft sample). Production dispatch in `RecurringCollector._postCollectCallback` discards
 * returndata, so this divergence does not affect the gas accounting under measurement.
 */
contract AfterCollectionGasReportingMock {
    /// @notice No-op warm-up target. Returning a value is irrelevant — the probe only runs
    /// this to warm `payer`'s entry on the access list before the timed CALL.
    /// @param payer Ignored.
    /// @return Always true.
    function isEligible(address payer) external pure returns (bool) {
        payer;
        return true;
    }

    /// @notice Returns the `gasleft()` value observed at function entry. View so the probe
    /// can be invoked via `eth_call` (Hardhat `staticCall`) without committing state.
    /// @param agreementId Ignored.
    /// @param tokens Ignored.
    /// @return The result of `gasleft()` at function entry.
    function afterCollection(bytes16 agreementId, uint256 tokens) external view returns (uint256) {
        agreementId;
        tokens;
        return gasleft();
    }
}

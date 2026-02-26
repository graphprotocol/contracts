// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

/**
 * @title Interface for contracts that can act as authorized agreement approvers
 * @author Edge & Node
 * @notice Enables contracts to authorize RCA agreements and updates on-chain via
 * {RecurringCollector.acceptUnsigned} and {RecurringCollector.updateUnsigned},
 * replacing ECDSA signatures with a callback.
 *
 * Uses the magic-value pattern: return the function selector on success.
 *
 * The same callback is used for both accept (RCA hash) and update (RCAU hash).
 * Hash namespaces do not collide because RCA and RCAU use different EIP712 type hashes.
 *
 * No per-payer authorization step is needed — the contract's code is the authorization.
 * The trust chain is: governance grants operator role → operator registers
 * (validates and pre-funds) → isAuthorizedAgreement confirms → RC accepts/updates.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IContractApprover {
    /**
     * @notice Confirms this contract authorized the given agreement or update
     * @dev Called by {RecurringCollector.acceptUnsigned} with an RCA hash or by
     * {RecurringCollector.updateUnsigned} with an RCAU hash to verify authorization.
     * @param agreementHash The EIP712 hash of the RCA or RCAU struct
     * @return magic `IContractApprover.isAuthorizedAgreement.selector` if authorized
     */
    function isAuthorizedAgreement(bytes32 agreementHash) external view returns (bytes4);
}

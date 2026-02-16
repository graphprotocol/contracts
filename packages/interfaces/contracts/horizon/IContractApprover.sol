// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

/**
 * @title Interface for contracts that can act as authorized agreement approvers
 * @author Edge & Node
 * @notice Enables contracts to authorize RCA agreements on-chain via
 * {RecurringCollector.acceptFromContract}, replacing ECDSA signatures with a callback.
 *
 * Uses the magic-value pattern: return the function selector on success.
 *
 * No per-payer authorization step is needed — the contract's code is the authorization.
 * The trust chain is: governance grants operator role → operator calls prepareAgreement
 * (validates position) → isAuthorizedAgreement confirms → RC accepts.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IContractApprover {
    /**
     * @notice Confirms this contract authorized the creation of the given agreement
     * @dev Called by {RecurringCollector.acceptFromContract} to verify the contract
     * created and approved the specific RCA identified by its EIP712 hash.
     * @param agreementHash The EIP712 hash of the RecurringCollectionAgreement struct
     * @return magic `IContractApprover.isAuthorizedAgreement.selector` if authorized
     */
    function isAuthorizedAgreement(bytes32 agreementHash) external view returns (bytes4);
}

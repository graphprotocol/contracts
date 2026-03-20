// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

/**
 * @title Interface for contract payer callbacks from RecurringCollector
 * @author Edge & Node
 * @notice Callbacks that RecurringCollector invokes on contract payers (payers with
 * deployed code, as opposed to EOA payers that use ECDSA signatures).
 *
 * Three callbacks:
 * - {approveAgreement}: gate — called during accept/update to verify authorization.
 *   Uses the magic-value pattern (return selector on success). Called with RCA hash
 *   on accept, RCAU hash on update; namespaces don't collide (different EIP712 type hashes).
 * - {beforeCollection}: called before PaymentsEscrow.collect() so the payer can top up
 *   escrow if needed. Only acts when the escrow balance is short for the collection.
 * - {afterCollection}: called after collection so the payer can reconcile escrow state.
 * Both collection callbacks are wrapped in try/catch — reverts do not block collection.
 *
 * No per-payer authorization step is needed — the contract's code is the authorization.
 * The trust chain is: governance grants operator role → operator registers
 * (validates and pre-funds) → approveAgreement confirms → RC accepts/updates.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IAgreementOwner {
    /**
     * @notice Confirms this contract authorized the given agreement or update
     * @dev Called by {RecurringCollector.accept} with an RCA hash or by
     * {RecurringCollector.update} with an RCAU hash to verify authorization (empty authData path).
     *
     * WARNING: This function provides no replay protection. It returns approval for any
     * hash that was previously authorized, regardless of how many times it is called.
     * Collectors MUST ensure that agreement acceptance is a one-way state transition
     * (e.g. NotAccepted → Accepted with no path back) to prevent replay of approved hashes.
     * @param agreementHash The EIP712 hash of the RCA or RCAU struct
     * @return magic `IAgreementOwner.approveAgreement.selector` if authorized
     */
    function approveAgreement(bytes32 agreementHash) external view returns (bytes4);

    /**
     * @notice Called by RecurringCollector before PaymentsEscrow.collect()
     * @dev Allows contract payers to top up escrow if the balance is insufficient
     * for the upcoming collection. Wrapped in try/catch — reverts do not block collection.
     * @param agreementId The agreement being collected
     * @param tokensToCollect Amount of tokens about to be collected
     */
    function beforeCollection(bytes16 agreementId, uint256 tokensToCollect) external;

    /**
     * @notice Called by RecurringCollector after a successful collection
     * @dev Allows contract payers to reconcile escrow state in the same transaction
     * as the collection. Wrapped in try/catch — reverts do not block collection.
     * @param agreementId The collected agreement
     * @param tokensCollected Amount of tokens collected
     */
    function afterCollection(bytes16 agreementId, uint256 tokensCollected) external;
}

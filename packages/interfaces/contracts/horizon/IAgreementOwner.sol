// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

/**
 * @title Interface for contract payer callbacks from RecurringCollector
 * @author Edge & Node
 * @notice Callbacks that RecurringCollector invokes on contract payers that opt in
 * via the CONDITION_AGREEMENT_OWNER offer condition.
 *
 * @dev Opt-in is enforced at acceptance: an offer that sets CONDITION_AGREEMENT_OWNER
 * is only acceptable if the payer reports support for this interface via ERC-165
 * (`supportsInterface(type(IAgreementOwner).interfaceId)` returns true).
 *
 * Collection callbacks:
 * - {beforeCollection}: called before PaymentsEscrow.collect() so the payer can top up
 *   escrow if needed. Only acts when the escrow balance is short for the collection.
 * - {afterCollection}: called after collection so the payer can reconcile escrow state.
 * Both collection callbacks are wrapped in try/catch — reverts do not block collection.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IAgreementOwner {
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

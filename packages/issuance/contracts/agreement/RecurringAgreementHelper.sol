// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { IRecurringAgreementHelper } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementHelper.sol";
import { IRecurringAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManager.sol";

/**
 * @title RecurringAgreementHelper
 * @author Edge & Node
 * @notice Stateless convenience contract that provides batch reconciliation
 * functions for {RecurringAgreementManager}. Each call delegates to the
 * manager's single-agreement `reconcileAgreement`.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringAgreementHelper is IRecurringAgreementHelper {
    /// @notice The RecurringAgreementManager contract
    IRecurringAgreementManager public immutable MANAGER;

    /// @notice Thrown when the manager address is the zero address
    error ManagerZeroAddress();

    /**
     * @notice Constructor for the RecurringAgreementHelper contract
     * @param manager Address of the RecurringAgreementManager contract
     */
    constructor(address manager) {
        require(manager != address(0), ManagerZeroAddress());
        MANAGER = IRecurringAgreementManager(manager);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function reconcile(address provider) external {
        bytes16[] memory agreementIds = MANAGER.getProviderAgreements(provider);
        for (uint256 i = 0; i < agreementIds.length; ++i) {
            MANAGER.reconcileAgreement(agreementIds[i]);
        }
    }

    /// @inheritdoc IRecurringAgreementHelper
    function reconcileBatch(bytes16[] calldata agreementIds) external {
        for (uint256 i = 0; i < agreementIds.length; ++i) {
            if (MANAGER.getAgreementInfo(agreementIds[i]).provider == address(0)) continue;
            MANAGER.reconcileAgreement(agreementIds[i]);
        }
    }
}

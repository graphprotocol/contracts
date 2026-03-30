// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { REGISTERED, ACCEPTED } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

/// @notice Tests for view functions: getAgreementData (isCollectable, collectionSeconds), getMaxNextClaim.
contract RecurringCollectorViewFunctionsTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== getAgreementData collectability ====================

    function test_GetAgreementData_Accepted(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Advance past minSecondsPerCollection so it's collectable
        skip(rca.minSecondsPerCollection);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);

        assertTrue(agreement.isCollectable, "Accepted agreement should be collectable");
        assertTrue(agreement.collectionSeconds > 0, "Collection seconds should be > 0");
    }

    function test_GetAgreementData_CanceledBySP(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        _cancelByProvider(rca, agreementId);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);

        assertFalse(agreement.isCollectable, "CanceledBySP should not be collectable");
    }

    function test_GetAgreementData_None() public view {
        // Query a non-existent agreement
        bytes16 fakeId = bytes16(keccak256("nonexistent"));
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(fakeId);

        assertFalse(agreement.isCollectable);
    }

    function test_GetAgreementData_CanceledByPayer_SameBlock(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Payer cancel in the same block as accept — zero time elapsed since acceptedAt.
        _cancelByPayer(rca, agreementId);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        // collectionEnd == collectionStart -> ZeroCollectionSeconds regardless of notice period
        assertFalse(agreement.isCollectable, "Same-block cancel should not be collectable (zero elapsed time)");
    }

    function test_GetAgreementData_CanceledByPayer_WithWindow(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        skip(rca.minSecondsPerCollection + 100);
        _cancelByPayer(rca, agreementId);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);

        assertTrue(agreement.isCollectable, "CanceledByPayer with elapsed time should be collectable");
        assertTrue(agreement.collectionSeconds > 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

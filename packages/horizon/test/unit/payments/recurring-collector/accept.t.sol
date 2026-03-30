// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorAcceptTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Accept(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (, bytes16 agreementId) = _sensibleAccept(fuzzyTestAccept);
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertEq(agreement.state, REGISTERED | ACCEPTED);
    }

    function test_Accept_Revert_WhenAcceptanceDeadlineElapsed(
        FuzzyTestAccept calldata fuzzyTestAccept,
        uint256 unboundedSkip
    ) public {
        // Store an offer while deadline is still valid
        (, bytes16 agreementId) = _sensibleOffer(fuzzyTestAccept);
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;

        // Decode the deadline from the active offer
        (, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        IRecurringCollector.RecurringCollectionAgreement memory rca = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreement)
        );
        uint64 deadline = rca.deadline;

        // Skip time past the deadline
        skip(boundSkip(unboundedSkip, 1, type(uint64).max - block.timestamp));
        vm.assume(block.timestamp > deadline);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.AgreementDeadlineElapsed.selector,
            block.timestamp,
            deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(agreement.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);
    }

    function test_Accept_Revert_WhenAlreadyAccepted(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestAccept
        );

        // Re-offering the same RCA should fail in offer() because the agreement
        // is already in Accepted state (not NotAccepted)
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.AgreementIncorrectState.selector,
            agreementId,
            REGISTERED | ACCEPTED
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(acceptedRca), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

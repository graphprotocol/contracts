// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorAcceptTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Accept(FuzzyTestAccept calldata fuzzyTestAccept) public {
        _sensibleAuthorizeAndAccept(fuzzyTestAccept);
    }

    function test_Accept_Revert_WhenAcceptanceDeadlineElapsed(
        IRecurringCollector.RecurringCollectionAgreement memory fuzzyRCA,
        bytes memory fuzzySignature,
        uint256 unboundedSkip
    ) public {
        // Ensure non-empty signature so the signed path is taken (which checks deadline first)
        vm.assume(fuzzySignature.length > 0);
        // Generate deterministic agreement ID for validation
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            fuzzyRCA.payer,
            fuzzyRCA.dataService,
            fuzzyRCA.serviceProvider,
            fuzzyRCA.deadline,
            fuzzyRCA.nonce
        );
        vm.assume(agreementId != bytes16(0));
        skip(boundSkip(unboundedSkip, 1, type(uint64).max - block.timestamp));
        fuzzyRCA = _recurringCollectorHelper.withElapsedAcceptDeadline(fuzzyRCA);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
            block.timestamp,
            fuzzyRCA.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(fuzzyRCA.dataService);
        _recurringCollector.accept(fuzzyRCA, fuzzySignature);
    }

    function test_Accept_Revert_WhenAlreadyAccepted(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes memory signature,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            agreementId,
            IRecurringCollector.AgreementState.Accepted
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.accept(acceptedRca, signature);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

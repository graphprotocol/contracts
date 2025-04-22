// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "../../../contracts/interfaces/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorAcceptTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Accept(FuzzyAcceptableRCA memory fuzzyAcceptableRCA) public {
        _fuzzyAuthorizeAndAccept(fuzzyAcceptableRCA);
    }

    function test_Accept_Revert_WhenAcceptanceDeadlineElapsed(
        IRecurringCollector.SignedRCA memory fuzzySignedRCA,
        uint256 unboundedSkip
    ) public {
        skip(boundSkipFloor(unboundedSkip, 1));
        fuzzySignedRCA.rca = _recurringCollectorHelper.withElapsedAcceptDeadline(fuzzySignedRCA.rca);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
            fuzzySignedRCA.rca.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(fuzzySignedRCA.rca.dataService);
        _recurringCollector.accept(fuzzySignedRCA);
    }

    function test_Accept_Revert_WhenAlreadyAccepted(FuzzyAcceptableRCA memory fuzzyAcceptableRCA) public {
        IRecurringCollector.SignedRCA memory signedRCA = _fuzzyAuthorizeAndAccept(fuzzyAcceptableRCA);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementAlreadyAccepted.selector,
            signedRCA.rca.agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(signedRCA.rca.dataService);
        _recurringCollector.accept(signedRCA);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

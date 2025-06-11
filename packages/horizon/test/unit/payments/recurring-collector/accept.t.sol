// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "../../../../contracts/interfaces/IRecurringCollector.sol";

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
        IRecurringCollector.SignedRCA memory fuzzySignedRCA,
        uint256 unboundedSkip
    ) public {
        vm.assume(fuzzySignedRCA.rca.agreementId != bytes16(0));
        skip(boundSkip(unboundedSkip, 1, type(uint64).max - block.timestamp));
        fuzzySignedRCA.rca = _recurringCollectorHelper.withElapsedAcceptDeadline(fuzzySignedRCA.rca);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
            block.timestamp,
            fuzzySignedRCA.rca.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(fuzzySignedRCA.rca.dataService);
        _recurringCollector.accept(fuzzySignedRCA);
    }

    function test_Accept_Revert_WhenAlreadyAccepted(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (IRecurringCollector.SignedRCA memory accepted, ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            accepted.rca.agreementId,
            IRecurringCollector.AgreementState.Accepted
        );
        vm.expectRevert(expectedErr);
        vm.prank(accepted.rca.dataService);
        _recurringCollector.accept(accepted);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

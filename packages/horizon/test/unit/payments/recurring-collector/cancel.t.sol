// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IRecurringCollector } from "../../../../contracts/interfaces/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorCancelTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Cancel(FuzzyTestAccept calldata fuzzyTestAccept, uint8 unboundedCanceler) public {
        (IRecurringCollector.SignedRCA memory accepted, , bytes16 agreementId) = _sensibleAuthorizeAndAccept(
            fuzzyTestAccept
        );

        _cancel(accepted.rca, agreementId, _fuzzyCancelAgreementBy(unboundedCanceler));
    }

    function test_Cancel_Revert_WhenNotAccepted(
        IRecurringCollector.RecurringCollectionAgreement memory fuzzyRCA,
        uint8 unboundedCanceler
    ) public {
        // Generate deterministic agreement ID
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            fuzzyRCA.payer,
            fuzzyRCA.dataService,
            fuzzyRCA.serviceProvider,
            fuzzyRCA.deadline,
            fuzzyRCA.nonce
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            agreementId,
            IRecurringCollector.AgreementState.NotAccepted
        );
        vm.expectRevert(expectedErr);
        vm.prank(fuzzyRCA.dataService);
        _recurringCollector.cancel(agreementId, _fuzzyCancelAgreementBy(unboundedCanceler));
    }

    function test_Cancel_Revert_WhenNotDataService(
        FuzzyTestAccept calldata fuzzyTestAccept,
        uint8 unboundedCanceler,
        address notDataService
    ) public {
        vm.assume(fuzzyTestAccept.rca.dataService != notDataService);

        (, , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.cancel(agreementId, _fuzzyCancelAgreementBy(unboundedCanceler));
    }
    /* solhint-enable graph/func-name-mixedcase */
}

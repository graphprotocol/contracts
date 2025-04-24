// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "../../../contracts/interfaces/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorCancelTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Cancel(FuzzyTestAccept calldata fuzzyTestAccept) public {
        _sensibleAuthorizeAndAccept(fuzzyTestAccept);
        _cancel(fuzzyTestAccept.rca);
    }

    function test_Cancel_Revert_WhenNotAccepted(
        IRecurringCollector.RecurringCollectionAgreement memory fuzzyRCA
    ) public {
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNeverAccepted.selector,
            fuzzyRCA.agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(fuzzyRCA.dataService);
        _recurringCollector.cancel(fuzzyRCA.agreementId);
    }

    function test_Cancel_Revert_WhenNotDataService(
        FuzzyTestAccept calldata fuzzyTestAccept,
        address notDataService
    ) public {
        vm.assume(fuzzyTestAccept.rca.dataService != notDataService);

        _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            fuzzyTestAccept.rca.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.cancel(fuzzyTestAccept.rca.agreementId);
    }
    /* solhint-enable graph/func-name-mixedcase */
}

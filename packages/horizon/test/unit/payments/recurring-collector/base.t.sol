// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorBaseTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_RecoverRCASigner(FuzzyTestAccept memory fuzzyTestAccept) public view {
        uint256 signerKey = boundKey(fuzzyTestAccept.unboundedSignerKey);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes memory signature
        ) = _recurringCollectorHelper.generateSignedRCA(fuzzyTestAccept.rca, signerKey);

        assertEq(
            _recurringCollector.recoverRCASigner(rca, signature),
            vm.addr(signerKey),
            "Recovered RCA signer does not match"
        );
    }

    function test_RecoverRCAUSigner(FuzzyTestUpdate memory fuzzyTestUpdate) public view {
        uint256 signerKey = boundKey(fuzzyTestUpdate.fuzzyTestAccept.unboundedSignerKey);
        (
            IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau,
            bytes memory signature
        ) = _recurringCollectorHelper.generateSignedRCAU(fuzzyTestUpdate.rcau, signerKey);

        assertEq(
            _recurringCollector.recoverRCAUSigner(rcau, signature),
            vm.addr(signerKey),
            "Recovered RCAU signer does not match"
        );
    }

    /* solhint-enable graph/func-name-mixedcase */
}

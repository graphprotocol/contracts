// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "../../../contracts/interfaces/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorUpgradeTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Upgrade_Revert_WhenUpgradeElapsed(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 unboundedUpgradeSkip
    ) public {
        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);

        boundSkipCeil(unboundedUpgradeSkip, type(uint256).max);
        rcau.deadline = bound(rcau.deadline, 0, block.timestamp - 1);
        IRecurringCollector.SignedRCAU memory signedRCAU = IRecurringCollector.SignedRCAU({
            rcau: rcau,
            signature: ""
        });

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
            rcau.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_Revert_WhenNeverAccepted(IRecurringCollector.RecurringCollectionAgreement memory rca) public {
        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);

        rcau.deadline = block.timestamp;
        IRecurringCollector.SignedRCAU memory signedRCAU = IRecurringCollector.SignedRCAU({
            rcau: rcau,
            signature: ""
        });

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNeverAccepted.selector,
            rcau.agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_Revert_WhenDataServiceNotAuthorized(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 unboundedKey,
        uint256 unboundedUpgradeSkip,
        address notDataService
    ) public {
        vm.assume(rca.dataService != notDataService);
        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);
        uint256 signerKey = boundKey(unboundedKey);
        _authorizeAndAccept(rca, signerKey);

        boundSkipCeil(unboundedUpgradeSkip, type(uint256).max);
        rcau.deadline = boundTimestampMin(rcau.deadline, block.timestamp + 1);
        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            signerKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            rcau.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_Revert_WhenInvalidSigner(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 unboundedKey,
        uint256 unboundedUpgradeSkip,
        uint256 unboundedInvalidSignerKey
    ) public {
        uint256 signerKey = boundKey(unboundedKey);
        uint256 invalidSignerKey = boundKey(unboundedInvalidSignerKey);
        vm.assume(signerKey != invalidSignerKey);

        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);
        _authorizeAndAccept(rca, signerKey);

        boundSkipCeil(unboundedUpgradeSkip, type(uint256).max);
        rcau.deadline = boundTimestampMin(rcau.deadline, block.timestamp + 1);

        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            invalidSignerKey
        );

        vm.expectRevert(IRecurringCollector.RecurringCollectorInvalidSigner.selector);
        vm.prank(rca.dataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_OK(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 unboundedKey,
        uint256 unboundedUpgradeSkip
    ) public {
        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);
        uint256 signerKey = boundKey(unboundedKey);
        _authorizeAndAccept(rca, signerKey);

        boundSkipCeil(unboundedUpgradeSkip, type(uint256).max);
        rcau.deadline = boundTimestampMin(rcau.deadline, block.timestamp + 1);
        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            signerKey
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpgraded(
            rca.dataService,
            rca.payer,
            rca.serviceProvider,
            rcau.agreementId,
            block.timestamp,
            rcau.duration,
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection
        );
        vm.prank(rca.dataService);
        _recurringCollector.upgrade(signedRCAU);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(rca.agreementId);
        assertEq(rcau.duration, agreement.duration);
        assertEq(rcau.maxInitialTokens, agreement.maxInitialTokens);
        assertEq(rcau.maxOngoingTokensPerSecond, agreement.maxOngoingTokensPerSecond);
        assertEq(rcau.minSecondsPerCollection, agreement.minSecondsPerCollection);
        assertEq(rcau.maxSecondsPerCollection, agreement.maxSecondsPerCollection);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

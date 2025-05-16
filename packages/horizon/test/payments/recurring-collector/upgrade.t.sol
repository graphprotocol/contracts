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
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau,
        uint256 unboundedUpgradeSkip
    ) public {
        rca = _recurringCollectorHelper.sensibleRCA(rca);
        rcau = _recurringCollectorHelper.sensibleRCAU(rcau);
        rcau.agreementId = rca.agreementId;

        boundSkipCeil(unboundedUpgradeSkip, type(uint64).max);
        rcau.deadline = uint64(bound(rcau.deadline, 0, block.timestamp - 1));
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

    function test_Upgrade_Revert_WhenNeverAccepted(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau
    ) public {
        rca = _recurringCollectorHelper.sensibleRCA(rca);
        rcau = _recurringCollectorHelper.sensibleRCAU(rcau);
        rcau.agreementId = rca.agreementId;

        rcau.deadline = uint64(block.timestamp);
        IRecurringCollector.SignedRCAU memory signedRCAU = IRecurringCollector.SignedRCAU({
            rcau: rcau,
            signature: ""
        });

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            rcau.agreementId,
            IRecurringCollector.AgreementState.NotAccepted
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_Revert_WhenDataServiceNotAuthorized(
        FuzzyTestUpgrade calldata fuzzyTestUpgrade,
        address notDataService
    ) public {
        vm.assume(fuzzyTestUpgrade.fuzzyTestAccept.rca.dataService != notDataService);
        (IRecurringCollector.SignedRCA memory accepted, uint256 signerKey) = _sensibleAuthorizeAndAccept(
            fuzzyTestUpgrade.fuzzyTestAccept
        );

        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpgrade.rcau
        );
        rcau.agreementId = accepted.rca.agreementId;

        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            signerKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            signedRCAU.rcau.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_Revert_WhenInvalidSigner(
        FuzzyTestUpgrade calldata fuzzyTestUpgrade,
        uint256 unboundedInvalidSignerKey
    ) public {
        (IRecurringCollector.SignedRCA memory accepted, uint256 signerKey) = _sensibleAuthorizeAndAccept(
            fuzzyTestUpgrade.fuzzyTestAccept
        );
        uint256 invalidSignerKey = boundKey(unboundedInvalidSignerKey);
        vm.assume(signerKey != invalidSignerKey);

        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpgrade.rcau
        );
        rcau.agreementId = accepted.rca.agreementId;

        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            invalidSignerKey
        );

        vm.expectRevert(IRecurringCollector.RecurringCollectorInvalidSigner.selector);
        vm.prank(accepted.rca.dataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_OK(FuzzyTestUpgrade calldata fuzzyTestUpgrade) public {
        (IRecurringCollector.SignedRCA memory accepted, uint256 signerKey) = _sensibleAuthorizeAndAccept(
            fuzzyTestUpgrade.fuzzyTestAccept
        );
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpgrade.rcau
        );
        rcau.agreementId = accepted.rca.agreementId;
        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            signerKey
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpgraded(
            accepted.rca.dataService,
            accepted.rca.payer,
            accepted.rca.serviceProvider,
            rcau.agreementId,
            uint64(block.timestamp),
            rcau.endsAt,
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection
        );
        vm.prank(accepted.rca.dataService);
        _recurringCollector.upgrade(signedRCAU);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(accepted.rca.agreementId);
        assertEq(rcau.endsAt, agreement.endsAt);
        assertEq(rcau.maxInitialTokens, agreement.maxInitialTokens);
        assertEq(rcau.maxOngoingTokensPerSecond, agreement.maxOngoingTokensPerSecond);
        assertEq(rcau.minSecondsPerCollection, agreement.minSecondsPerCollection);
        assertEq(rcau.maxSecondsPerCollection, agreement.maxSecondsPerCollection);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

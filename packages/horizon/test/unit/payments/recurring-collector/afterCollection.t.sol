// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    OFFER_TYPE_NEW,
    IAgreementCollector
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

/// @notice Tests for IAgreementOwner.beforeCollection and .afterCollection in RecurringCollector._collect()
contract RecurringCollectorAfterCollectionTest is RecurringCollectorSharedTest {
    function _newApprover() internal returns (MockAgreementOwner) {
        return new MockAgreementOwner();
    }

    function _acceptUnsignedAgreement(
        MockAgreementOwner approver
    ) internal returns (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) {
        rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(approver),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            })
        );

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Payer calls offer
        vm.prank(address(approver));
        agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Data service accepts with stored hash
        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);
    }

    /* solhint-disable graph/func-name-mixedcase */

    function test_BeforeCollection_CallbackInvoked() public {
        MockAgreementOwner approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);

        // beforeCollection should have been called with the tokens about to be collected
        assertEq(approver.lastBeforeCollectionAgreementId(), agreementId);
        assertEq(approver.lastBeforeCollectionTokens(), tokens);
    }

    function test_BeforeCollection_CollectionSucceedsWhenCallbackReverts() public {
        MockAgreementOwner approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        approver.setShouldRevertOnBeforeCollection(true);

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        // Collection should still succeed despite beforeCollection reverting
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);

        // beforeCollection state not updated (it reverted), but afterCollection still runs
        assertEq(approver.lastBeforeCollectionAgreementId(), bytes16(0));
        assertEq(approver.lastCollectedAgreementId(), agreementId);
    }

    function test_AfterCollection_CallbackInvoked() public {
        MockAgreementOwner approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        // Skip past minSecondsPerCollection and collect
        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);

        // Verify callback was invoked with correct parameters
        assertEq(approver.lastCollectedAgreementId(), agreementId);
        assertEq(approver.lastCollectedTokens(), tokens);
    }

    function test_AfterCollection_CollectionSucceedsWhenCallbackReverts() public {
        MockAgreementOwner approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        // Configure callback to revert
        approver.setShouldRevertOnCollected(true);

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        // Expect PayerCallbackFailed event for the afterCollection stage
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.PayerCallbackFailed(
            agreementId,
            address(approver),
            IAgreementCollector.PayerCallbackStage.AfterCollection
        );

        // Collection should still succeed despite callback reverting
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);

        // Callback state should not have been updated (it reverted)
        assertEq(approver.lastCollectedAgreementId(), bytes16(0));
        assertEq(approver.lastCollectedTokens(), 0);
    }

    function test_Collect_Revert_WhenInsufficientCallbackGas() public {
        MockAgreementOwner approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        // Encode the outer collect call
        bytes memory callData = abi.encodeCall(
            _recurringCollector.collect,
            (IGraphPayments.PaymentTypes.IndexingFee, data)
        );

        // Binary-search for a gas limit that passes core collect logic but trips the
        // callback gas guard (gasleft < MAX_CALLBACK_GAS * 64/63 ≈ 1_523_810).
        // Core logic + escrow call + beforeCollection + events uses ~200k gas.
        bool triggered;
        for (uint256 gasLimit = 1_700_000; gasLimit > 1_500_000; gasLimit -= 10_000) {
            uint256 snap = vm.snapshot();
            vm.prank(rca.dataService);
            (bool success, bytes memory returnData) = address(_recurringCollector).call{ gas: gasLimit }(callData);
            if (!success && returnData.length >= 4) {
                bytes4 selector;
                assembly {
                    selector := mload(add(returnData, 32))
                }
                if (selector == IRecurringCollector.InsufficientCallbackGas.selector) {
                    triggered = true;
                    assertTrue(vm.revertTo(snap));
                    break;
                }
            }
            assertTrue(vm.revertTo(snap));
        }
        assertTrue(triggered, "Should have triggered InsufficientCallbackGas at some gas limit");
    }

    function test_AfterCollection_NotCalledForEOAPayer(FuzzyTestCollect calldata fuzzy) public {
        // EOA payer — no contract code, so afterCollection is skipped
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _sensibleAccept(
            fuzzy.fuzzyTestAccept
        );

        (bytes memory data, uint256 collectionSeconds, uint256 tokens) = _generateValidCollection(
            acceptedRca,
            fuzzy.collectParams,
            fuzzy.collectParams.tokens, // reuse as skip seed
            fuzzy.collectParams.tokens
        );

        skip(collectionSeconds);
        // Should succeed without any callback issues (EOA has no code)
        vm.prank(acceptedRca.dataService);
        uint256 collected = _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
        assertEq(collected, tokens);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

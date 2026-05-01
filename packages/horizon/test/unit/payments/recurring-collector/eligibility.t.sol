// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";
import { BareAgreementOwner } from "./BareAgreementOwner.t.sol";
import { MalformedERC165Payer } from "./MalformedERC165Payer.t.sol";

/// @notice Tests for the IProviderEligibility gate in RecurringCollector._collect()
contract RecurringCollectorEligibilityTest is RecurringCollectorSharedTest {
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
                nonce: 1,
                metadata: ""
            })
        );
        rca.conditions = 1; // CONDITION_ELIGIBILITY_CHECK — set after sensibleRCA

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        agreementId = _recurringCollector.accept(rca, "");
    }

    /* solhint-disable graph/func-name-mixedcase */

    function test_Collect_OK_WhenEligible() public {
        MockAgreementOwner approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        // Provider is eligible by default — isEligible returns true
        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);
    }

    function test_Collect_Revert_WhenNotEligible() public {
        MockAgreementOwner approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        // Explicitly mark provider as ineligible
        approver.setProviderIneligible(rca.serviceProvider);

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorCollectionNotEligible.selector,
                agreementId,
                rca.serviceProvider
            )
        );
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_OK_WhenPayerDoesNotImplementEligibility() public {
        // BareAgreementOwner implements IAgreementOwner but NOT IProviderEligibility.
        // The isEligible call will revert — treated as "no opinion" (collection proceeds).
        BareAgreementOwner bare = new BareAgreementOwner();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(bare),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        vm.prank(address(bare));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        // Collection succeeds — revert from missing isEligible is treated as "no opinion"
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);
    }

    function test_Collect_OK_WhenEOAPayer(FuzzyTestCollect calldata fuzzy) public {
        // Use standard ECDSA-signed path (EOA payer)
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        (bytes memory data, uint256 collectionSeconds, uint256 tokens) = _generateValidCollection(
            acceptedRca,
            fuzzy.collectParams,
            fuzzy.collectParams.tokens,
            fuzzy.collectParams.tokens
        );

        skip(collectionSeconds);
        // EOA payer has no code — eligibility check is skipped entirely
        vm.prank(acceptedRca.dataService);
        uint256 collected = _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
        assertEq(collected, tokens);
    }

    function test_Collect_OK_ZeroTokensSkipsEligibilityCheck() public {
        MockAgreementOwner approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        // Provider is ineligible, but zero-token collection should skip the gate
        approver.setProviderIneligible(rca.serviceProvider);

        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), 0, 0));

        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, 0);
    }

    function test_Collect_OK_WhenPayerReturnsMalformedData() public {
        // A malicious payer returns empty data from isEligible (via fallback).
        // The call succeeds at the EVM level but returndata is empty — treated as
        // "no opinion" (collection proceeds), not a caller-side revert.
        MalformedERC165Payer malicious = new MalformedERC165Payer();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(malicious),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        vm.prank(address(malicious));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        // Collection must succeed — malformed returndata must not block collection
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

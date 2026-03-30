// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";
import { BareAgreementOwner } from "./BareAgreementOwner.t.sol";
import { MalformedERC165Payer } from "./MalformedERC165Payer.t.sol";

/// @notice Tests for the IProviderEligibility gate in RecurringCollector._collect()
/// and the ERC-165 validation of CONDITION_ELIGIBILITY_CHECK at offer time.
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
                conditions: 1, // CONDITION_ELIGIBILITY_CHECK
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            })
        );

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Payer calls offer
        vm.prank(address(approver));
        agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Service provider accepts with stored hash
        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);
    }

    /* solhint-disable graph/func-name-mixedcase */

    // ── Collection-time eligibility checks ──────────────────────────────

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
            abi.encodeWithSelector(IRecurringCollector.CollectionNotEligible.selector, agreementId, rca.serviceProvider)
        );
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
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

    function test_Collect_OK_WithoutEligibilityCondition(FuzzyTestCollect calldata fuzzy) public {
        // EOA payer — no CONDITION_ELIGIBILITY_CHECK
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _sensibleAccept(
            fuzzy.fuzzyTestAccept
        );

        (bytes memory data, uint256 collectionSeconds, uint256 tokens) = _generateValidCollection(
            acceptedRca,
            fuzzy.collectParams,
            fuzzy.collectParams.tokens,
            fuzzy.collectParams.tokens
        );

        skip(collectionSeconds);
        // EOA payer — conditions masked to exclude CONDITION_ELIGIBILITY_CHECK by sensibleRCA
        vm.prank(acceptedRca.dataService);
        uint256 collected = _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
        assertEq(collected, tokens);
    }

    // ── Offer-time ERC-165 validation ───────────────────────────────────

    function test_Offer_Revert_WhenPayerDoesNotSupportEligibility() public {
        // BareAgreementOwner implements IAgreementOwner but NOT IERC165/IProviderEligibility.
        // Offer must be rejected — CONDITION_ELIGIBILITY_CHECK requires ERC-165 confirmation
        // to prevent slipping in an apparently-inert condition that could later deny payments.
        BareAgreementOwner bare = new BareAgreementOwner();

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: address(bare),
            dataService: makeAddr("ds"),
            serviceProvider: makeAddr("sp"),
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 1, // CONDITION_ELIGIBILITY_CHECK
            minSecondsPayerCancellationNotice: 0,
            nonce: 1,
            metadata: ""
        });
        rca = _recurringCollectorHelper.sensibleRCA(rca);
        // sensibleRCA won't mask conditions because payer has code — but it doesn't support the interface
        rca.conditions = 1; // force it back in case sensibleRCA touched it

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.EligibilityConditionNotSupported.selector, address(bare))
        );
        vm.prank(address(bare));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    function test_Offer_Revert_WhenPayerReturnsMalformedERC165() public {
        // MalformedERC165Payer has a fallback returning empty data — ERC165Checker
        // correctly detects this as non-compliant and the offer must be rejected.
        MalformedERC165Payer malicious = new MalformedERC165Payer();

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: address(malicious),
            dataService: makeAddr("ds"),
            serviceProvider: makeAddr("sp"),
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 1, // CONDITION_ELIGIBILITY_CHECK
            minSecondsPayerCancellationNotice: 0,
            nonce: 1,
            metadata: ""
        });
        rca = _recurringCollectorHelper.sensibleRCA(rca);
        rca.conditions = 1;

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.EligibilityConditionNotSupported.selector, address(malicious))
        );
        vm.prank(address(malicious));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    function test_Offer_Revert_WhenEOAPayerSetsEligibilityCondition() public {
        // EOA payers cannot implement IProviderEligibility — offer must be rejected
        // to prevent an apparently-inert condition from being slipped in.
        address eoa = makeAddr("eoa-payer");

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: eoa,
            dataService: makeAddr("ds"),
            serviceProvider: makeAddr("sp"),
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 1, // CONDITION_ELIGIBILITY_CHECK
            minSecondsPayerCancellationNotice: 0,
            nonce: 1,
            metadata: ""
        });
        rca = _recurringCollectorHelper.sensibleRCA(rca);
        rca.conditions = 1; // force — sensibleRCA masks it for EOAs

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.EligibilityConditionNotSupported.selector, eoa));
        vm.prank(eoa);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    function test_Offer_OK_WhenEligibilityCapablePayer() public {
        // MockAgreementOwner implements IERC165 + IProviderEligibility — offer succeeds
        MockAgreementOwner approver = _newApprover();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
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
                conditions: 1, // CONDITION_ELIGIBILITY_CHECK
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            })
        );

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(address(approver));
        IRecurringCollector.AgreementDetails memory result = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        assertTrue(result.agreementId != bytes16(0));
    }

    function test_Offer_OK_WhenEligibilityCapablePayerWithoutCondition() public {
        // Even if payer supports IProviderEligibility, offers WITHOUT the condition are valid.
        // Eligibility checks are opt-in per agreement.
        MockAgreementOwner approver = _newApprover();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
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
                conditions: 0, // No eligibility check
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            })
        );

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(address(approver));
        IRecurringCollector.AgreementDetails memory result = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        assertTrue(result.agreementId != bytes16(0));
    }

    /* solhint-enable graph/func-name-mixedcase */
}

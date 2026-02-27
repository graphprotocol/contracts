// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockContractApprover } from "./MockContractApprover.t.sol";
import { BareContractApprover } from "./BareContractApprover.t.sol";

/// @notice Tests for the IRewardsEligibility gate in RecurringCollector._collect()
contract RecurringCollectorEligibilityTest is RecurringCollectorSharedTest {
    function _newApprover() internal returns (MockContractApprover) {
        return new MockContractApprover();
    }

    function _acceptUnsignedAgreement(
        MockContractApprover approver
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
                nonce: 1,
                metadata: ""
            })
        );

        bytes32 agreementHash = _recurringCollector.hashRCA(rca);
        approver.authorize(agreementHash);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        agreementId = _recurringCollector.accept(rca, "");
    }

    /* solhint-disable graph/func-name-mixedcase */

    function test_Collect_OK_WhenEligible() public {
        MockContractApprover approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        // Enable eligibility check and mark provider as eligible
        approver.setEligibilityEnabled(true);
        approver.setProviderEligible(rca.serviceProvider, true);

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);
    }

    function test_Collect_Revert_WhenNotEligible() public {
        MockContractApprover approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        // Enable eligibility check but provider is NOT eligible
        approver.setEligibilityEnabled(true);
        // defaultEligible is false, and provider not explicitly set

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

    function test_Collect_OK_WhenPayerDoesNotSupportInterface() public {
        MockContractApprover approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        // eligibilityEnabled is false by default — supportsInterface returns false for IRewardsEligibility
        // Collection should proceed normally (backward compatible)

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

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

    function test_Collect_OK_WhenPayerHasNoERC165() public {
        // BareContractApprover implements IContractApprover but NOT IERC165.
        // The supportsInterface call will revert, hitting the catch {} branch.
        BareContractApprover bare = new BareContractApprover();

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
                nonce: 1,
                metadata: ""
            })
        );

        bytes32 agreementHash = _recurringCollector.hashRCA(rca);
        bare.authorize(agreementHash);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        // Collection succeeds — the catch {} swallows the revert from supportsInterface
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);
    }

    function test_Collect_OK_ZeroTokensSkipsEligibilityCheck() public {
        MockContractApprover approver = _newApprover();
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _acceptUnsignedAgreement(
            approver
        );

        // Enable eligibility check, provider is NOT eligible
        approver.setEligibilityEnabled(true);
        // defaultEligible = false

        // Zero-token collection should NOT trigger the eligibility gate
        // (the guard is inside `if (0 < tokensToCollect && ...)`)
        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), 0, 0));

        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

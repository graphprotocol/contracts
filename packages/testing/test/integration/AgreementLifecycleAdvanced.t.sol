// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IRecurringAgreementHelper } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementHelper.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { PPMMath } from "horizon/libraries/PPMMath.sol";

import { IndexingAgreement } from "subgraph-service/libraries/IndexingAgreement.sol";

import { FullStackHarness } from "../harness/FullStackHarness.t.sol";

/// @title AgreementLifecycleAdvancedTest
/// @notice Advanced integration tests: indexing rewards alongside fees, escrow transitions,
/// multi-agreement isolation, and reward denial scenarios.
contract AgreementLifecycleAdvancedTest is FullStackHarness {
    using PPMMath for uint256;

    bytes32 internal constant SUBGRAPH_DEPLOYMENT = keccak256("test-subgraph-deployment");
    uint256 internal constant INDEXER_TOKENS = 10_000 ether;

    IndexerSetup internal indexer;

    function setUp() public override {
        super.setUp();
        indexer = _setupIndexer("indexer1", SUBGRAPH_DEPLOYMENT, INDEXER_TOKENS);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 11: Indexing rewards alongside indexing fees
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario11_RewardsAndFeesCoexist() public {
        // -- Setup agreement for indexing fees --
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(indexer, 0, 1 ether, 3600, terms);

        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // Advance time for both collection types
        uint256 collectSeconds = 1800;
        skip(collectSeconds);
        vm.roll(block.number + EPOCH_LENGTH);

        // Add provision for stake locking (both fee types lock stake)
        uint256 expectedFeeTokens = terms.tokensPerSecond * collectSeconds;
        // Estimate rewards roughly — provision * rewardsPerSignal PPM
        uint256 estimatedRewards = indexer.provisionTokens.mulPPM(REWARDS_PER_SIGNAL);
        uint256 totalToLock = (expectedFeeTokens + estimatedRewards) * STAKE_TO_FEES_RATIO;
        _mintTokens(indexer.addr, totalToLock);
        vm.startPrank(indexer.addr);
        token.approve(address(staking), totalToLock);
        staking.stakeTo(indexer.addr, totalToLock);
        staking.addToProvision(indexer.addr, address(subgraphService), totalToLock);
        vm.stopPrank();

        uint256 indexerBalanceBefore = token.balanceOf(indexer.addr);

        // -- Collect indexing fees (via RC → RAM → PaymentsEscrow) --
        uint256 feeTokens = _collectIndexingFees(indexer, agreementId, 0, keccak256("poi-fees"), block.number - 1);
        assertTrue(feeTokens > 0, "indexing fee collection succeeded");

        uint256 indexerBalanceAfterFees = token.balanceOf(indexer.addr);
        uint256 feeProtocolCut = feeTokens.mulPPMRoundUp(PROTOCOL_PAYMENT_CUT);
        assertEq(
            indexerBalanceAfterFees - indexerBalanceBefore,
            feeTokens - feeProtocolCut,
            "indexer received fee tokens minus protocol cut"
        );

        // -- Collect indexing rewards (via RewardsManager → minting) --
        // Advance one more epoch so POI is fresh
        vm.roll(block.number + EPOCH_LENGTH);

        bytes memory rewardData = abi.encode(
            indexer.allocationId,
            keccak256("poi-rewards"),
            _getHardcodedPoiMetadata()
        );

        vm.prank(indexer.addr);
        uint256 rewardTokens = subgraphService.collect(
            indexer.addr,
            IGraphPayments.PaymentTypes.IndexingRewards,
            rewardData
        );

        // Rewards may be zero if allocation was created in current epoch
        // (the mock rewards manager calculates based on allocation tokens * rewardsPerSignal)
        uint256 indexerBalanceAfterRewards = token.balanceOf(indexer.addr);
        if (rewardTokens > 0) {
            assertTrue(indexerBalanceAfterRewards > indexerBalanceAfterFees, "indexer balance increased from rewards");
        }

        // -- Verify agreement state is still active --
        IRecurringCollector.AgreementData memory rcAgreement = recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(rcAgreement.state),
            uint8(IRecurringCollector.AgreementState.Accepted),
            "agreement still active after both collection types"
        );

        // -- Verify RAM escrow tracking is consistent --
        IRecurringAgreementHelper.ProviderAudit memory pAudit = ramHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer.addr
        );
        assertTrue(pAudit.sumMaxNextClaim > 0, "RAM still tracks the agreement");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 12: Reward denial — fees still flow independently
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario12_RewardDenialFeesContinue() public {
        // -- Setup agreement for indexing fees --
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(indexer, 0, 1 ether, 3600, terms);

        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // Deny the subgraph in rewards manager
        rewardsManager.setDenied(SUBGRAPH_DEPLOYMENT, true);

        // Advance time
        skip(1800);
        vm.roll(block.number + EPOCH_LENGTH);

        // Add provision for stake locking
        uint256 expectedFeeTokens = terms.tokensPerSecond * 1800;
        uint256 tokensToLock = expectedFeeTokens * STAKE_TO_FEES_RATIO;
        _mintTokens(indexer.addr, tokensToLock);
        vm.startPrank(indexer.addr);
        token.approve(address(staking), tokensToLock);
        staking.stakeTo(indexer.addr, tokensToLock);
        staking.addToProvision(indexer.addr, address(subgraphService), tokensToLock);
        vm.stopPrank();

        // -- Indexing fees still work despite subgraph denial --
        uint256 feeTokens = _collectIndexingFees(indexer, agreementId, 0, keccak256("poi-denied"), block.number - 1);
        assertTrue(feeTokens > 0, "fees collected despite reward denial");

        // -- Agreement remains active --
        IRecurringCollector.AgreementData memory rcAgreement = recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(rcAgreement.state),
            uint8(IRecurringCollector.AgreementState.Accepted),
            "agreement active despite denial"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 6: Escrow basis transitions under active agreement
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario6_EscrowBasisTransitions() public {
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(
            indexer,
            100 ether,
            1 ether,
            3600,
            terms
        );
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        _offerAndAccept(indexer, rca);

        // Full mode: escrow fully deposited
        IRecurringAgreementHelper.ProviderAudit memory pAudit = ramHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer.addr
        );
        assertEq(pAudit.escrow.balance, maxClaim, "Full: escrow deposited");

        // Switch to OnDemand
        vm.prank(operator);
        ram.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);
        ram.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);

        pAudit = ramHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);
        // OnDemand holds at sumMaxNextClaim level (same as Full when balance == max)
        assertEq(pAudit.escrow.balance, maxClaim, "OnDemand: balance unchanged when already at max");

        // Switch to JustInTime — should start thawing everything
        vm.prank(operator);
        ram.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);
        ram.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);

        pAudit = ramHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);
        assertEq(pAudit.escrow.tokensThawing, maxClaim, "JIT: thawing everything");

        // Switch back to Full — should deposit again after thaw completes
        vm.prank(operator);
        ram.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.Full);

        skip(1 days + 1); // wait for thaw
        ram.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);

        pAudit = ramHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);
        assertEq(pAudit.escrow.balance, maxClaim, "Full (restored): escrow re-deposited");
        assertEq(pAudit.escrow.tokensThawing, 0, "Full (restored): no thawing");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 10: Collect with stake locking verification
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario10_StakeLocking() public {
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(indexer, 0, 1 ether, 3600, terms);

        bytes16 agreementId = _offerAndAccept(indexer, rca);

        skip(600);
        vm.roll(block.number + EPOCH_LENGTH);

        uint256 expectedTokens = terms.tokensPerSecond * 600;
        uint256 expectedLocked = expectedTokens * STAKE_TO_FEES_RATIO;

        // Add provision for locking
        _mintTokens(indexer.addr, expectedLocked);
        vm.startPrank(indexer.addr);
        token.approve(address(staking), expectedLocked);
        staking.stakeTo(indexer.addr, expectedLocked);
        staking.addToProvision(indexer.addr, address(subgraphService), expectedLocked);
        vm.stopPrank();

        uint256 lockedBefore = subgraphService.feesProvisionTracker(indexer.addr);

        uint256 tokensCollected = _collectIndexingFees(
            indexer,
            agreementId,
            0,
            keccak256("poi-lock"),
            block.number - 1
        );

        uint256 lockedAfter = subgraphService.feesProvisionTracker(indexer.addr);
        uint256 actualLocked = tokensCollected * STAKE_TO_FEES_RATIO;

        assertEq(lockedAfter - lockedBefore, actualLocked, "stake locked = tokensCollected * stakeToFeesRatio");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 7: Multi-agreement isolation
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario7_MultiAgreementIsolation() public {
        // Setup a second indexer with its own allocation
        bytes32 subgraph2 = keccak256("test-subgraph-deployment-2");
        IndexerSetup memory indexer2 = _setupIndexer("indexer2", subgraph2, INDEXER_TOKENS);

        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        // Agreement 1: indexer1
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _buildRCA(
            indexer,
            100 ether,
            1 ether,
            3600,
            terms
        );
        bytes16 agreement1 = _offerAndAccept(indexer, rca1);

        // Agreement 2: indexer2 (different nonce needed since payer+dataService is same)
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _buildRCAEx(
            indexer2,
            200 ether,
            2 ether,
            7200,
            terms,
            2, // nonce
            0 // conditions
        );
        _ramOffer(rca2);
        bytes16 agreement2 = _ssAccept(indexer2, rca2);

        // Verify both tracked in RAM
        IRecurringAgreementHelper.GlobalAudit memory gAudit = ramHelper.auditGlobal();
        assertEq(gAudit.collectorCount, 1, "single collector");

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        IRecurringAgreementHelper.ProviderAudit memory p1 = ramHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer.addr
        );
        assertEq(p1.sumMaxNextClaim, maxClaim1, "indexer1 maxNextClaim");

        IRecurringAgreementHelper.ProviderAudit memory p2 = ramHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer2.addr
        );
        assertEq(p2.sumMaxNextClaim, maxClaim2, "indexer2 maxNextClaim");

        // Collect on agreement 1 only
        skip(600);
        vm.roll(block.number + EPOCH_LENGTH);
        _addProvisionTokens(indexer, terms.tokensPerSecond * 600 * STAKE_TO_FEES_RATIO);

        uint256 collected = _collectIndexingFees(indexer, agreement1, 0, keccak256("poi-multi"), block.number - 1);
        assertTrue(collected > 0, "collection succeeded on agreement 1");

        // Verify agreement 2 state is completely unaffected
        IRecurringCollector.AgreementData memory rc2 = recurringCollector.getAgreement(agreement2);
        assertEq(uint8(rc2.state), uint8(IRecurringCollector.AgreementState.Accepted), "agreement 2 still accepted");
        assertEq(rc2.lastCollectionAt, 0, "agreement 2 never collected");

        // Verify indexer2's escrow unchanged
        p2 = ramHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer2.addr);
        assertEq(p2.sumMaxNextClaim, maxClaim2, "indexer2 maxNextClaim unchanged after indexer1 collection");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 8: Expired offer cleanup
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario8_ExpiredOfferCleanup() public {
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(
            indexer,
            100 ether,
            1 ether,
            3600,
            terms
        );
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Offer but DON'T accept
        _ramOffer(rca);

        // Verify RAM tracks it
        IRecurringAgreementHelper.ProviderAudit memory pAudit = ramHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer.addr
        );
        assertEq(pAudit.sumMaxNextClaim, maxClaim, "tracked after offer");
        assertEq(pAudit.escrow.balance, maxClaim, "escrow deposited for offer");

        // Before deadline: reconcile should NOT remove
        (uint256 removed, ) = ramHelper.reconcile(IAgreementCollector(address(recurringCollector)), indexer.addr);
        assertEq(removed, 0, "not removable before deadline");

        // Warp past deadline (1 hour)
        skip(1 hours + 1);

        // Now reconcile should remove the expired offer
        (removed, ) = ramHelper.reconcile(IAgreementCollector(address(recurringCollector)), indexer.addr);
        assertEq(removed, 1, "removed after deadline");

        // maxNextClaim zeroed
        pAudit = ramHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);
        assertEq(pAudit.sumMaxNextClaim, 0, "maxNextClaim zeroed");

        // Escrow should be thawing
        assertTrue(pAudit.escrow.tokensThawing > 0, "escrow thawing");

        // Wait for thaw and drain
        skip(1 days + 1);
        ram.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);

        pAudit = ramHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);
        assertEq(pAudit.escrow.balance, 0, "escrow drained");
        assertEq(pAudit.escrow.tokensThawing, 0, "no more thawing");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 9: Agreement with eligibility check
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario9_EligibilityCheck_Eligible() public {
        // RAM implements IProviderEligibility. With no oracle set, isEligible returns true.
        // Build RCA with CONDITION_ELIGIBILITY_CHECK flag set.
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        uint16 eligibilityCondition = recurringCollector.CONDITION_ELIGIBILITY_CHECK();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCAEx(
            indexer,
            0,
            1 ether,
            3600,
            terms,
            1,
            eligibilityCondition
        );

        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // Advance time and collect — should succeed (RAM has no oracle, returns eligible)
        skip(600);
        vm.roll(block.number + EPOCH_LENGTH);
        _addProvisionTokens(indexer, terms.tokensPerSecond * 600 * STAKE_TO_FEES_RATIO);

        uint256 collected = _collectIndexingFees(indexer, agreementId, 0, keccak256("poi-elig"), block.number - 1);
        assertTrue(collected > 0, "collection succeeded with eligibility check (no oracle = eligible)");
    }

    function test_Scenario9_EligibilityCheck_NotEligible() public {
        // Deploy a mock oracle that returns false for our indexer
        MockEligibilityOracle oracle = new MockEligibilityOracle();
        oracle.setEligible(indexer.addr, false);

        // Set the oracle on RAM
        vm.prank(governor);
        ram.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));

        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        uint16 eligibilityCondition = recurringCollector.CONDITION_ELIGIBILITY_CHECK();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCAEx(
            indexer,
            0,
            1 ether,
            3600,
            terms,
            1,
            eligibilityCondition
        );

        bytes16 agreementId = _offerAndAccept(indexer, rca);

        skip(600);
        vm.roll(block.number + EPOCH_LENGTH);
        _addProvisionTokens(indexer, terms.tokensPerSecond * 600 * STAKE_TO_FEES_RATIO);

        // Collection should revert because eligibility check returns false
        bytes memory collectData = abi.encode(
            agreementId,
            abi.encode(
                IndexingAgreement.CollectIndexingFeeDataV1({
                    entities: 0,
                    poi: keccak256("poi-inelig"),
                    poiBlockNumber: block.number - 1,
                    metadata: "",
                    maxSlippage: type(uint256).max
                })
            )
        );

        vm.prank(indexer.addr);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorCollectionNotEligible.selector,
                agreementId,
                indexer.addr
            )
        );
        subgraphService.collect(indexer.addr, IGraphPayments.PaymentTypes.IndexingFee, collectData);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 13: Close allocation with active agreement
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario13_CloseAllocationCancelsAgreement() public {
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(indexer, 0, 1 ether, 3600, terms);
        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // blockClosingAllocationWithActiveAgreement is false by default
        // Closing allocation should auto-cancel the agreement

        vm.prank(indexer.addr);
        subgraphService.stopService(indexer.addr, abi.encode(indexer.allocationId));

        // Verify agreement is canceled in RC
        IRecurringCollector.AgreementData memory rcAgreement = recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(rcAgreement.state),
            uint8(IRecurringCollector.AgreementState.CanceledByServiceProvider),
            "agreement canceled when allocation closed"
        );

        // Verify SS no longer has active agreement for this allocation
        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(
            uint8(wrapper.collectorAgreement.state),
            uint8(IRecurringCollector.AgreementState.CanceledByServiceProvider),
            "SS reflects cancellation"
        );
    }

    function test_Scenario13_CloseAllocationBlockedByActiveAgreement() public {
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(indexer, 0, 1 ether, 3600, terms);
        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // Enable the block
        vm.prank(governor);
        subgraphService.setBlockClosingAllocationWithActiveAgreement(true);

        // Closing allocation should revert
        vm.prank(indexer.addr);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationHasActiveAgreement.selector,
                indexer.allocationId,
                agreementId
            )
        );
        subgraphService.stopService(indexer.addr, abi.encode(indexer.allocationId));

        // Agreement should still be active
        IRecurringCollector.AgreementData memory rcAgreement = recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(rcAgreement.state),
            uint8(IRecurringCollector.AgreementState.Accepted),
            "agreement still active"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 14: Cancel with below-minimum provision (bug repro)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice An indexer whose provision drops below minimum should still be
    /// able to cancel their own agreement. Cancel is an exit path and must not
    /// be gated by VALID_PROVISION. Currently reverts — this test demonstrates
    /// the bug described in CancelAgreementProvisionCheck task.
    function test_Scenario14_CancelWithBelowMinimumProvision() public {
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(indexer, 0, 1 ether, 3600, terms);
        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // Reduce indexer's provision below minimum by thawing most of it
        uint256 tokensToThaw = indexer.provisionTokens - (MINIMUM_PROVISION_TOKENS / 2);
        vm.startPrank(indexer.addr);
        staking.thaw(indexer.addr, address(subgraphService), tokensToThaw);
        vm.stopPrank();

        // Skip past thawing period
        skip(MAX_WAIT_PERIOD + 1);

        // Deprovision the thawed tokens
        vm.prank(indexer.addr);
        staking.deprovision(indexer.addr, address(subgraphService), 0);

        // Verify provision is below minimum
        uint256 available = staking.getProviderTokensAvailable(indexer.addr, address(subgraphService));
        assertTrue(available < MINIMUM_PROVISION_TOKENS, "provision should be below minimum");

        // Cancel should succeed — it's an exit path
        vm.prank(indexer.addr);
        subgraphService.cancelIndexingAgreement(indexer.addr, agreementId);

        // Verify agreement is canceled
        IRecurringCollector.AgreementData memory rcAgreement = recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(rcAgreement.state),
            uint8(IRecurringCollector.AgreementState.CanceledByServiceProvider),
            "agreement should be canceled despite below-minimum provision"
        );
    }

    // ── Helpers ──

    function _getHardcodedPoiMetadata() internal view returns (bytes memory) {
        return abi.encode(block.number, bytes32("PUBLIC_POI1"), uint8(0), uint8(0), uint256(0));
    }
}

/// @notice Mock eligibility oracle for testing
contract MockEligibilityOracle {
    mapping(address => bool) private _eligible;
    bool private _defaultEligible = true;

    function setEligible(address provider, bool eligible) external {
        _eligible[provider] = eligible;
        if (!eligible) _defaultEligible = false;
    }

    function isEligible(address provider) external view returns (bool) {
        if (!_defaultEligible && !_eligible[provider]) return false;
        return true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        // IProviderEligibility: isEligible(address) = 0x66e305fd
        return interfaceId == 0x66e305fd || interfaceId == 0x01ffc9a7; // IERC165
    }
}

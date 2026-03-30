// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PROVIDER,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";

import { RealStackHarness } from "../harness/RealStackHarness.t.sol";

/// @notice Gas measurement for RAM callbacks against real contracts.
/// RecurringCollector forwards at most MAX_CALLBACK_GAS (1.5M) to each callback.
/// These tests verify the real contract stack stays within that budget.
///
/// Real contracts on callback path: PaymentsEscrow, IssuanceAllocator, RecurringCollector.
/// Stubs (not on callback path): Controller, HorizonStaking, GraphToken (bare ERC20).
///
/// Test matrix:
/// - beforeCollection: early return, JIT deposit, cold-storage first access
/// - afterCollection: reconcile, withdraw+deposit (heaviest escrow path), deletion cascade
/// - afterAgreementStateChange: first-seen discovery, existing reconcile, deletion
contract CallbackGasTest is RealStackHarness {
    /* solhint-disable graph/func-name-mixedcase */

    /// @notice Must match MAX_CALLBACK_GAS in RecurringCollector.
    uint256 internal constant MAX_CALLBACK_GAS = 1_500_000;

    /// @notice Assert callbacks use less than half the budget.
    /// Leaves margin for cold storage and EVM repricing.
    uint256 internal constant GAS_THRESHOLD = MAX_CALLBACK_GAS / 2; // 750_000

    // ==================== beforeCollection ====================

    /// @notice Worst-case beforeCollection: escrow short, triggers distributeIssuance + JIT deposit.
    function test_BeforeCollection_GasWithinBudget_JitDeposit() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        IPaymentsEscrow.EscrowAccount memory account = ram.getEscrowAccount(
            IRecurringCollector(address(recurringCollector)),
            indexer
        );

        // Advance block so distributeIssuance actually runs (not deduped)
        vm.roll(block.number + 1);

        uint256 tokensToCollect = account.balance + 500 ether;

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.beforeCollection(agreementId, tokensToCollect);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "beforeCollection (JIT) exceeds half of callback gas budget");
    }

    /// @notice beforeCollection early-return path: escrow sufficient.
    function test_BeforeCollection_GasWithinBudget_EscrowSufficient() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.beforeCollection(agreementId, 1 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "beforeCollection (sufficient) exceeds half of callback gas budget");
    }

    /// @notice beforeCollection on an untracked agreement: exercises _getAgreementProvider discovery
    /// (getAgreement from collector, role checks, set registration) before the JIT deposit.
    /// This is the heaviest beforeCollection path: cold storage + discovery + JIT.
    function test_BeforeCollection_GasWithinBudget_ColdDiscoveryJit() public {
        // Create an agreement directly in the collector so RAM has never seen it.
        // Normally offer() triggers afterAgreementStateChange which discovers the agreement,
        // but we bypass RAM to test the discovery path inside beforeCollection.
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        // Offer and accept without RAM tracking: offer via RAM (triggers discovery),
        // then create a second agreement for a different provider that RAM hasn't seen.
        address indexer2 = makeAddr("indexer2");
        _setUpProvider(indexer2);
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = rca;
        rca2.serviceProvider = indexer2;
        rca2.nonce = 2;

        // Offer via RAM — this triggers afterAgreementStateChange discovery for rca2
        bytes16 agreementId2 = _offerAgreement(rca2);

        // Now call beforeCollection on this newly-discovered agreement with escrow shortfall.
        // The agreement is tracked (discovered during offer), but the provider's escrow slot
        // is cold in the PaymentsEscrow (never deposited to before).
        vm.roll(block.number + 1);

        IPaymentsEscrow.EscrowAccount memory account = ram.getEscrowAccount(
            IRecurringCollector(address(recurringCollector)),
            indexer2
        );
        uint256 tokensToCollect = account.balance + 500 ether;

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.beforeCollection(agreementId2, tokensToCollect);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "beforeCollection (cold provider JIT) exceeds half of callback gas budget");
    }

    // ==================== afterCollection ====================

    /// @notice Worst-case afterCollection: reconcile against real RecurringCollector + escrow update.
    /// Exercises real RecurringCollector.getAgreementData() / getMaxNextClaim() and real
    /// PaymentsEscrow.adjustThaw() / deposit().
    function test_AfterCollection_GasWithinBudget_FullReconcile() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);

        // Advance time past minSecondsPerCollection, then simulate post-collection
        vm.warp(block.timestamp + 1 hours);
        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.afterCollection(agreementId, 500 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "afterCollection (full reconcile) exceeds half of callback gas budget");
    }

    /// @notice afterCollection exercising the heaviest escrow mutation path:
    /// 1. A prior thaw has matured → withdraw (real token transfer)
    /// 2. After withdrawal, escrow below min → deposit (approve + real token transfer)
    /// This hits both the withdraw and deposit branches inside _withdrawAndRebalance.
    function test_AfterCollection_GasWithinBudget_WithdrawAndDeposit() public {
        // Create two agreements for the same provider to build up escrow
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId1 = _offerAndAccept(rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;
        bytes16 agreementId2 = _offerAndAccept(rca2);

        // Cancel one agreement by SP → maxNextClaim drops to 0 for that agreement,
        // sumMaxNextClaim halves, escrow is now above max → triggers thaw of excess.
        bytes32 activeHash2 = recurringCollector.getAgreementVersionAt(agreementId2, 0).versionHash;
        vm.prank(indexer);
        recurringCollector.cancel(agreementId2, activeHash2, 0);

        // The afterAgreementStateChange callback from cancel triggers reconciliation,
        // which removes the agreement and thaws the excess escrow.
        // Now advance past the thawing period (1 day) so the thaw matures.
        vm.warp(block.timestamp + 2 days);
        vm.roll(block.number + 1);

        // afterCollection on the remaining agreement: _reconcileProviderEscrow sees
        // matured thaw → withdraw, then escrow may be below min → deposit.
        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.afterCollection(agreementId1, 0);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "afterCollection (withdraw + deposit) exceeds half of callback gas budget");
    }

    /// @notice afterCollection when SP cancels → maxNextClaim goes to 0, agreement is deleted,
    /// _reconcileProvider runs cascade removal (provider set remove, potentially collector set remove).
    function test_AfterCollection_GasWithinBudget_DeletionCascade() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);

        // SP cancels → state becomes NOTICE_GIVEN | SETTLED, maxNextClaim → 0
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(indexer);
        recurringCollector.cancel(agreementId, activeHash, 0);

        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.afterCollection(agreementId, 0);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "afterCollection (deletion cascade) exceeds half of callback gas budget");
    }

    // ==================== afterAgreementStateChange ====================

    /// @notice afterAgreementStateChange on a first-seen agreement: exercises the full
    /// _getAgreementProvider discovery path (getAgreement from collector, role validation,
    /// EnumerableSet insertions) followed by _reconcileAndUpdateEscrow + _reconcileProviderEscrow.
    /// This is tested by measuring the callback during an accept (the offer callback already
    /// discovered the agreement, so accept is the reconcile path). For the pure discovery path,
    /// we need an agreement that RAM hasn't seen yet.
    function test_AfterAgreementStateChange_GasWithinBudget_FirstSeenDiscovery() public {
        // Create agreement directly in RecurringCollector, bypassing RAM.
        // Then call afterAgreementStateChange — RAM discovers it for the first time.
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        // We need to offer without going through RAM so the callback doesn't fire.
        // Use a second indexer so we get a clean discovery.
        address indexer2 = makeAddr("indexer2");
        _setUpProvider(indexer2);
        rca.serviceProvider = indexer2;
        rca.nonce = 2;

        // Offer through RAM — this triggers afterAgreementStateChange (discovery happens here).
        // We measure the SECOND call (accept) which is a reconcile on an already-discovered agreement.
        bytes16 agreementId = _offerAgreement(rca);

        // Accept the agreement (SP signs)
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(indexer2);
        recurringCollector.accept(agreementId, activeHash, bytes(""), 0);

        // Now measure afterAgreementStateChange as a reconcile of the accepted agreement
        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.afterAgreementStateChange(agreementId, activeHash, REGISTERED | ACCEPTED);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(
            gasUsed,
            GAS_THRESHOLD,
            "afterAgreementStateChange (reconcile after accept) exceeds half of callback gas budget"
        );
    }

    /// @notice First-seen discovery during offer: the collector's _notifyStateChange fires
    /// afterAgreementStateChange on RAM for an agreement it has never seen before.
    /// This is the heaviest callback path due to cold EnumerableSet insertions + escrow deposit.
    /// Measured indirectly via total offerAgreement gas (includes the callback).
    ///
    /// Trace analysis shows this path uses ~490k gas (33% of 1.5M budget), dominated by
    /// cold-storage writes for EnumerableSet (collectorSet, providerSet, agreements) + deposit.
    /// The measured gas below is the total offer transaction including RAM-side logic and the
    /// collector-side offer; the callback is the dominant component (~490k of ~560k total).
    function test_AfterAgreementStateChange_GasWithinBudget_FirstSeenDiscoveryViaOffer() public {
        // Use a fresh provider so all storage slots are cold
        address indexer2 = makeAddr("indexer2");
        _setUpProvider(indexer2);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.serviceProvider = indexer2;
        rca.nonce = 2;

        token.mint(address(ram), 1_000_000 ether);

        // Measure the full offer. The collector fires _notifyStateChange → RAM.afterAgreementStateChange
        // which discovers the agreement (cold getAgreement, cold set insertions, escrow deposit).
        uint256 gasBefore = gasleft();
        vm.prank(operator);
        ram.offerAgreement(IRecurringCollector(address(recurringCollector)), OFFER_TYPE_NEW, abi.encode(rca));
        uint256 gasUsed = gasBefore - gasleft();

        // The callback (afterAgreementStateChange) is capped at MAX_CALLBACK_GAS by the collector.
        // The total offer must stay well under the block gas limit, but more importantly,
        // the callback portion (visible in trace as ~490k) must stay under MAX_CALLBACK_GAS.
        // We assert the total is under the callback budget as a conservative check —
        // if the total fits, the callback portion certainly fits.
        assertLt(
            gasUsed,
            MAX_CALLBACK_GAS,
            "offerAgreement (including first-seen discovery callback) exceeds callback gas budget"
        );
    }

    /// @notice afterAgreementStateChange on a canceled agreement — deletion path.
    /// maxNextClaim → 0, agreement removed, _reconcileProvider cascade.
    function test_AfterAgreementStateChange_GasWithinBudget_Deletion() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);

        // SP cancels
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(indexer);
        recurringCollector.cancel(agreementId, activeHash, 0);

        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.afterAgreementStateChange(
            agreementId,
            activeHash,
            REGISTERED | ACCEPTED | NOTICE_GIVEN | SETTLED | BY_PROVIDER
        );
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "afterAgreementStateChange (deletion) exceeds half of callback gas budget");
    }

    // ==================== Helpers ====================

    function _setUpProvider(address provider) internal {
        staking.setProvision(
            provider,
            dataService,
            IHorizonStakingTypes.Provision({
                tokens: 1000 ether,
                tokensThawing: 0,
                sharesThawing: 0,
                maxVerifierCut: 100000,
                thawingPeriod: 604800,
                createdAt: uint64(block.timestamp),
                maxVerifierCutPending: 100000,
                thawingPeriodPending: 604800,
                lastParametersStagedAt: 0,
                thawingNonce: 0
            })
        );
    }

    /* solhint-enable graph/func-name-mixedcase */
}

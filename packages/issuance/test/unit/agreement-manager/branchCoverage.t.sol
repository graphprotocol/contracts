// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManager } from "../../../contracts/agreement/RecurringAgreementManager.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";
import { MockIssuanceAllocator } from "./mocks/MockIssuanceAllocator.sol";

/// @notice Targeted tests for uncovered branches in RecurringAgreementManager.
contract RecurringAgreementManagerBranchCoverageTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    // ══════════════════════════════════════════════════════════════════════
    //  setIssuanceAllocator — ERC165 validation (L305)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Setting allocator to an address that does not support IIssuanceAllocationDistribution reverts.
    function test_SetIssuanceAllocator_Revert_InvalidERC165() public {
        // Use an address with code but wrong interface (the mock collector doesn't implement IIssuanceAllocationDistribution)
        vm.prank(governor);
        vm.expectRevert(
            abi.encodeWithSelector(
                RecurringAgreementManager.InvalidIssuanceAllocator.selector,
                address(recurringCollector)
            )
        );
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(address(recurringCollector)));
    }

    /// @notice Setting allocator to an EOA (no code) also fails ERC165 check.
    function test_SetIssuanceAllocator_Revert_EOA() public {
        address eoa = makeAddr("randomEOA");
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(RecurringAgreementManager.InvalidIssuanceAllocator.selector, eoa));
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(eoa));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  offerAgreement — unauthorized collector (L372)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice offerAgreement reverts when collector lacks COLLECTOR_ROLE.
    function test_OfferAgreement_Revert_UnauthorizedCollector() public {
        MockRecurringCollector rogue = new MockRecurringCollector();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.payer = address(agreementManager);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringAgreementManagement.UnauthorizedCollector.selector, address(rogue))
        );
        agreementManager.offerAgreement(IRecurringCollector(address(rogue)), OFFER_TYPE_NEW, abi.encode(rca));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  offerAgreement — payer mismatch
    // ══════════════════════════════════════════════════════════════════════

    /// @notice offerAgreement reverts when collector returns payer != address(this).
    function test_OfferAgreement_Revert_PayerMismatch() public {
        address wrongPayer = makeAddr("wrongPayer");
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.payer = wrongPayer; // mock will return this as-is

        token.mint(address(agreementManager), 1_000_000 ether);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IRecurringAgreementManagement.PayerMismatch.selector, wrongPayer));
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  offerAgreement — zero service provider (L378)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice offerAgreement reverts when collector returns serviceProvider = address(0).
    function test_OfferAgreement_Revert_ZeroServiceProvider() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.serviceProvider = address(0); // mock will return this as-is

        token.mint(address(agreementManager), 1_000_000 ether);

        vm.prank(operator);
        vm.expectRevert(IRecurringAgreementManagement.ServiceProviderZeroAddress.selector);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  offerAgreement — unauthorized data service (L379)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice offerAgreement reverts when the returned dataService lacks DATA_SERVICE_ROLE.
    function test_OfferAgreement_Revert_UnauthorizedDataService() public {
        address rogueDS = makeAddr("rogueDataService");
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.dataService = rogueDS; // not granted DATA_SERVICE_ROLE

        token.mint(address(agreementManager), 1_000_000 ether);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringAgreementManagement.UnauthorizedDataService.selector, rogueDS)
        );
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  forceRemoveAgreement (L412–424)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice forceRemoveAgreement is a no-op when the agreement is unknown (provider == address(0)).
    function test_ForceRemoveAgreement_NoOp_UnknownAgreement() public {
        bytes16 unknownId = bytes16(keccak256("nonexistent"));

        // Should not revert — early return
        vm.prank(operator);
        agreementManager.forceRemoveAgreement(IAgreementCollector(address(recurringCollector)), unknownId);

        // No state changes
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
    }

    /// @notice forceRemoveAgreement removes a tracked agreement.
    function test_ForceRemoveAgreement_RemovesTracked() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Verify tracked
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
        assertTrue(agreementManager.getSumMaxNextClaim(_collector(), indexer) > 0);

        // Force remove
        vm.prank(operator);
        agreementManager.forceRemoveAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // Cleaned up
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(), 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  emergencyRevokeRole (L437–439)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice emergencyRevokeRole reverts when attempting to revoke GOVERNOR_ROLE.
    function test_EmergencyRevokeRole_Revert_CannotRevokeGovernor() public {
        // Grant PAUSE_ROLE to governor for this test
        vm.prank(governor);
        agreementManager.grantRole(PAUSE_ROLE, governor);

        vm.prank(governor);
        vm.expectRevert(RecurringAgreementManager.CannotRevokeGovernorRole.selector);
        agreementManager.emergencyRevokeRole(GOVERNOR_ROLE, governor);
    }

    /// @notice emergencyRevokeRole succeeds for non-governor roles.
    function test_EmergencyRevokeRole_Success() public {
        // Grant PAUSE_ROLE to an account
        address pauseGuardian = makeAddr("pauseGuardian");
        vm.prank(governor);
        agreementManager.grantRole(PAUSE_ROLE, pauseGuardian);

        // Grant a role to revoke
        address target = makeAddr("target");
        vm.prank(operator);
        agreementManager.grantRole(AGREEMENT_MANAGER_ROLE, target);
        assertTrue(agreementManager.hasRole(AGREEMENT_MANAGER_ROLE, target));

        // Emergency revoke
        vm.prank(pauseGuardian);
        agreementManager.emergencyRevokeRole(AGREEMENT_MANAGER_ROLE, target);
        assertFalse(agreementManager.hasRole(AGREEMENT_MANAGER_ROLE, target));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  _withdrawAndRebalance — deposit deficit branch (L854/857–862)
    // ══════════════════════════════════════════════════════════════════════

    // ══════════════════════════════════════════════════════════════════════
    //  getIssuanceAllocator — view getter (L281-282)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice getIssuanceAllocator returns the configured allocator and the
    /// zero default prior to setIssuanceAllocator.
    function test_GetIssuanceAllocator_ReturnsConfiguredValue() public {
        assertEq(address(agreementManager.getIssuanceAllocator()), address(0), "Default allocator must be zero");

        MockIssuanceAllocator allocator = new MockIssuanceAllocator(token, address(agreementManager));
        vm.prank(governor);
        agreementManager.setIssuanceAllocator(allocator);

        assertEq(
            address(agreementManager.getIssuanceAllocator()),
            address(allocator),
            "Configured allocator must be returned"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    //  offerAgreement — collector returns zero agreementId (L361)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice A conformant collector must return a non-zero agreementId; RAM
    /// enforces this invariant with AgreementIdZero.
    function test_OfferAgreement_Revert_AgreementIdZero() public {
        ZeroIdCollector rogue = new ZeroIdCollector(dataService, address(agreementManager), indexer);
        vm.prank(governor);
        agreementManager.grantRole(COLLECTOR_ROLE, address(rogue));

        // Payload content is irrelevant — the mock returns a zero agreementId unconditionally.
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        vm.expectRevert(IRecurringAgreementManagement.AgreementIdZero.selector);
        agreementManager.offerAgreement(IAgreementCollector(address(rogue)), OFFER_TYPE_NEW, abi.encode(rca));
    }

    /// @notice When escrow balance drops below min (after collection), reconcile deposits the deficit.
    function test_WithdrawAndRebalance_DepositDeficit() public {
        // Offer agreement in Full mode — escrow gets fully funded
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _offerAgreement(rca);

        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether; // 3700 ether

        // Verify fully funded
        (uint256 balBefore, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(balBefore, expectedMaxClaim);

        // Simulate collection draining most of the escrow:
        // Set escrow balance to a small amount (below min), no thawing
        uint256 drainedBalance = 100 ether; // well below min = expectedMaxClaim in Full mode
        paymentsEscrow.setAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer,
            drainedBalance,
            0, // no thawing
            0 // no thaw end
        );

        // Manager still has tokens (minted 1M in _offerAgreement, deposited 3700)
        // Reconcile should trigger deposit deficit branch
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // After reconcile, escrow should be topped up
        (uint256 balAfter, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertTrue(balAfter > drainedBalance, "escrow should be topped up after reconcile");
    }

    /* solhint-enable graph/func-name-mixedcase */
}

/// @notice Minimal collector stub that returns a zero agreementId with valid
/// payer/dataService/serviceProvider, used to exercise RAM's AgreementIdZero guard.
contract ZeroIdCollector {
    address private immutable _dataService;
    address private immutable _payer;
    address private immutable _serviceProvider;

    constructor(address dataService_, address payer_, address serviceProvider_) {
        _dataService = dataService_;
        _payer = payer_;
        _serviceProvider = serviceProvider_;
    }

    function offer(
        uint8 /* offerType */,
        bytes calldata /* data */,
        uint16 /* options */
    ) external view returns (IAgreementCollector.AgreementDetails memory details) {
        details.agreementId = bytes16(0);
        details.payer = _payer;
        details.dataService = _dataService;
        details.serviceProvider = _serviceProvider;
    }
}

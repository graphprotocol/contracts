// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { RecurringAgreementManager } from "contracts/agreement/RecurringAgreementManager.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockIssuanceAllocator } from "./mocks/MockIssuanceAllocator.sol";

/// @notice Tests for _ensureIncomingDistributionToCurrentBlock integration: RAM calls distributeIssuance on the
/// allocator before making balance-dependent decisions in beforeCollection and _updateEscrow.
contract RecurringAgreementManagerEnsureDistributedTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    MockIssuanceAllocator internal mockAllocator;

    function setUp() public virtual override {
        super.setUp();
        mockAllocator = new MockIssuanceAllocator(token, address(agreementManager));
        vm.label(address(mockAllocator), "MockIssuanceAllocator");

        vm.prank(governor);
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(address(mockAllocator)));
    }

    // ==================== setIssuanceAllocator ====================

    function test_SetIssuanceAllocator_StoresAddress() public {
        MockIssuanceAllocator newAllocator = new MockIssuanceAllocator(token, address(agreementManager));

        vm.prank(governor);
        vm.expectEmit(address(agreementManager));
        emit IIssuanceTarget.IssuanceAllocatorSet(
            IIssuanceAllocationDistribution(address(mockAllocator)),
            IIssuanceAllocationDistribution(address(newAllocator))
        );
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(address(newAllocator)));
    }

    function test_SetIssuanceAllocator_Revert_WhenNotGovernor() public {
        vm.prank(operator);
        vm.expectRevert();
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(address(mockAllocator)));
    }

    function test_SetIssuanceAllocator_CanSetToZero() public {
        vm.prank(governor);
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(address(0)));
        // Should not revert — _ensureIncomingDistributionToCurrentBlock is a no-op with zero address
    }

    function test_SetIssuanceAllocator_NoopWhenUnchanged() public {
        vm.prank(governor);
        vm.recordLogs();
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(address(mockAllocator)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "should not emit when address unchanged");
    }

    // ==================== beforeCollection triggers distribution ====================

    function test_BeforeCollection_CallsDistributeWhenEscrowShort() public {
        // Set up: offer agreement so escrow is funded
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Get current escrow balance
        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Configure allocator to mint tokens on distribute
        mockAllocator.setMintPerDistribution(1000 ether);

        // Advance block so distribution will actually mint
        vm.roll(block.number + 1);

        // Request more than escrow — triggers JIT path which calls _ensureIncomingDistributionToCurrentBlock
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, escrowBalance + 500 ether);

        // Verify distributeIssuance was called
        assertGe(mockAllocator.distributeCallCount(), 1, "distributeIssuance should have been called");
    }

    function test_BeforeCollection_DistributionPreventsUnnecessaryTempJit() public {
        // Set up: offer agreement, drain RAM's free balance
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Burn RAM's free balance so it can't cover a JIT deposit without distribution
        uint256 freeBalance = token.balanceOf(address(agreementManager));
        vm.prank(address(agreementManager));
        token.transfer(address(1), freeBalance);
        assertEq(token.balanceOf(address(agreementManager)), 0);

        // Configure allocator to mint enough to cover the deficit plus 50% of sumMaxNextClaimAll reserve
        uint256 deficit = 500 ether;
        uint256 reserve = agreementManager.getSumMaxNextClaim(); // >= 50% threshold
        mockAllocator.setMintPerDistribution(deficit + reserve);

        // Advance block so distribution actually mints
        vm.roll(block.number + 1);

        // Without distribution, balance would be 0. With distribution, the allocator mints
        // tokens first, so JIT deposit succeeds.
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, escrowBalance + deficit);
    }

    function test_BeforeCollection_SkipsDistributeWhenEscrowSufficient() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Record count after offer (offerAgreement calls _updateEscrow which calls _ensureIncomingDistributionToCurrentBlock)
        uint256 countAfterOffer = mockAllocator.distributeCallCount();

        // Advance block so same-block dedup doesn't mask the early-return path
        vm.roll(block.number + 1);

        // Request less than escrow — early return before _ensureIncomingDistributionToCurrentBlock
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1 ether);

        assertEq(
            mockAllocator.distributeCallCount(),
            countAfterOffer,
            "should not call distribute when escrow sufficient"
        );
    }

    // ==================== _updateEscrow triggers distribution ====================

    function test_UpdateEscrow_CallsDistributeViaAfterCollection() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Simulate: agreement accepted and collected
        uint64 acceptedAt = uint64(block.timestamp);
        uint64 lastCollectionAt = uint64(block.timestamp + 1 hours);
        _setAgreementCollected(agreementId, rca, acceptedAt, lastCollectionAt);
        vm.warp(lastCollectionAt);

        vm.roll(block.number + 1);

        // afterCollection → _reconcileAndUpdateEscrow → _updateEscrow → _ensureIncomingDistributionToCurrentBlock
        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 500 ether);

        assertGe(mockAllocator.distributeCallCount(), 1, "distributeIssuance should be called via _updateEscrow");
    }

    function test_UpdateEscrow_CallsDistributeViaOfferAgreement() public {
        mockAllocator.setMintPerDistribution(100 ether);
        vm.roll(block.number + 1);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        // offerAgreement → _updateEscrow → _ensureIncomingDistributionToCurrentBlock
        _offerAgreement(rca);

        assertGe(mockAllocator.distributeCallCount(), 1, "distributeIssuance should be called via offerAgreement");
    }

    // ==================== No allocator set ====================

    function test_EnsureDistributed_NoopWhenAllocatorNotSet() public {
        // Clear allocator
        vm.prank(governor);
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(address(0)));

        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Mint extra tokens so JIT works without allocator
        token.mint(address(agreementManager), 1000 ether);

        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Should not revert even without allocator
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, escrowBalance + 500 ether);
    }

    // ==================== uint32 wrap ====================

    function test_EnsureDistributed_WorksAcrossUint32Boundary() public {
        // Use afterCollection path which always reaches _updateEscrow → _ensureIncomingDistributionToCurrentBlock,
        // regardless of escrow balance (unlike beforeCollection which has an early return).
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Set agreement as accepted so afterCollection reconciles
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        uint256 countBefore = mockAllocator.distributeCallCount();

        // Jump to uint32 max
        vm.roll(type(uint32).max);
        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 0);
        assertGt(mockAllocator.distributeCallCount(), countBefore, "should distribute at uint32.max");

        uint256 countAtMax = mockAllocator.distributeCallCount();

        // Cross the boundary: uint32.max + 1 wraps to 0 in uint32.
        // ensuredIncomingDistributedToBlock is uint32.max from the previous call, so no false match.
        vm.roll(uint256(type(uint32).max) + 1);
        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 0);
        assertGt(mockAllocator.distributeCallCount(), countAtMax, "should distribute after uint32 wrap to 0");

        uint256 countAfterWrap = mockAllocator.distributeCallCount();

        // Next block after wrap (wraps to 1) also works
        vm.roll(uint256(type(uint32).max) + 2);
        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 0);
        assertGt(mockAllocator.distributeCallCount(), countAfterWrap, "should distribute on block after wrap");
    }

    function test_EnsureDistributed_SameBlockDedup_AtUint32Boundary() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);
        token.mint(address(agreementManager), 10_000 ether);

        // Jump past the boundary
        vm.roll(uint256(type(uint32).max) + 3);
        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // First call distributes
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, escrowBalance + 1 ether);
        uint256 countAfterFirst = mockAllocator.distributeCallCount();

        // Second call same block — should NOT call distribute again
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, escrowBalance + 1 ether);
        assertEq(
            mockAllocator.distributeCallCount(),
            countAfterFirst,
            "should not distribute twice in same block after wrap"
        );
    }

    // ==================== setIssuanceAllocator ERC165 validation ====================

    function test_SetIssuanceAllocator_Revert_WhenNotERC165() public {
        // Deploy a contract that doesn't support ERC165
        address notAllocator = address(new NoERC165Contract());
        vm.prank(governor);
        vm.expectRevert(
            abi.encodeWithSelector(RecurringAgreementManager.InvalidIssuanceAllocator.selector, notAllocator)
        );
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(notAllocator));
    }

    function test_SetIssuanceAllocator_Revert_WhenEOA() public {
        address eoa = makeAddr("eoa");
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(RecurringAgreementManager.InvalidIssuanceAllocator.selector, eoa));
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(eoa));
    }

    // ==================== setIssuanceAllocator switches allocator ====================

    function test_SetIssuanceAllocator_NewAllocatorCalledNextBlock() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        // Switch allocator
        MockIssuanceAllocator newAllocator = new MockIssuanceAllocator(token, address(agreementManager));
        vm.prank(governor);
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(address(newAllocator)));

        // Next block: new allocator should be called via _updateEscrow
        vm.roll(block.number + 1);
        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 0);

        assertGe(newAllocator.distributeCallCount(), 1, "new allocator should be called on next block");
    }

    // ==================== distributeIssuance revert is caught ====================

    function test_EnsureDistributed_CatchesAllocatorRevert() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Mint tokens so JIT can still work even without distribution
        token.mint(address(agreementManager), 1000 ether);

        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Make allocator revert
        mockAllocator.setShouldRevert(true);
        vm.roll(block.number + 1);

        // beforeCollection should NOT revert — the distribution failure is caught
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, escrowBalance + 500 ether);
    }

    function test_EnsureDistributed_EmitsEventOnAllocatorRevert() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);
        token.mint(address(agreementManager), 1000 ether);

        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        mockAllocator.setShouldRevert(true);
        vm.roll(block.number + 1);

        vm.expectEmit(address(agreementManager));
        emit RecurringAgreementManager.DistributeIssuanceFailed(address(mockAllocator));

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, escrowBalance + 500 ether);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

/// @notice Helper contract with no ERC165 support for testing validation
contract NoERC165Contract {
    function doSomething() external pure returns (uint256) {
        return 42;
    }
}

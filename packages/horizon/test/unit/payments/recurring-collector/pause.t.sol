// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

/// @notice Tests for the pause mechanism in RecurringCollector.
contract RecurringCollectorPauseTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    address internal guardian = makeAddr("guardian");

    // Governor is address(0) in the mock controller
    function _governor() internal pure returns (address) {
        return address(0);
    }

    function _setGuardian(address who, bool allowed) internal {
        vm.prank(_governor());
        _recurringCollector.setPauseGuardian(who, allowed);
    }

    function _pause() internal {
        vm.prank(guardian);
        _recurringCollector.pause();
    }

    // ==================== setPauseGuardian ====================

    function test_SetPauseGuardian_OK() public {
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.PauseGuardianSet(guardian, true);
        _setGuardian(guardian, true);
        assertTrue(_recurringCollector.pauseGuardians(guardian));
    }

    function test_SetPauseGuardian_Remove() public {
        _setGuardian(guardian, true);

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.PauseGuardianSet(guardian, false);
        _setGuardian(guardian, false);
        assertFalse(_recurringCollector.pauseGuardians(guardian));
    }

    function test_SetPauseGuardian_Revert_WhenNotGovernor() public {
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorNotGovernor.selector, address(this))
        );
        _recurringCollector.setPauseGuardian(guardian, true);
    }

    function test_SetPauseGuardian_Revert_WhenNoChange() public {
        // guardian is not set, trying to set false (no change)
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorPauseGuardianNoChange.selector,
                guardian,
                false
            )
        );
        vm.prank(_governor());
        _recurringCollector.setPauseGuardian(guardian, false);
    }

    function test_SetPauseGuardian_Revert_WhenNoChange_AlreadySet() public {
        _setGuardian(guardian, true);

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorPauseGuardianNoChange.selector, guardian, true)
        );
        vm.prank(_governor());
        _recurringCollector.setPauseGuardian(guardian, true);
    }

    // ==================== pause / unpause ====================

    function test_Pause_OK() public {
        _setGuardian(guardian, true);
        assertFalse(_recurringCollector.paused());

        _pause();
        assertTrue(_recurringCollector.paused());
    }

    function test_Pause_Revert_WhenNotGuardian() public {
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorNotPauseGuardian.selector, address(this))
        );
        _recurringCollector.pause();
    }

    function test_Unpause_OK() public {
        _setGuardian(guardian, true);
        _pause();
        assertTrue(_recurringCollector.paused());

        vm.prank(guardian);
        _recurringCollector.unpause();
        assertFalse(_recurringCollector.paused());
    }

    function test_Unpause_Revert_WhenNotGuardian() public {
        _setGuardian(guardian, true);
        _pause();

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorNotPauseGuardian.selector, address(this))
        );
        _recurringCollector.unpause();
    }

    // ==================== whenNotPaused guards ====================

    function test_Accept_Revert_WhenPaused(FuzzyTestAccept calldata fuzzy) public {
        _setGuardian(guardian, true);
        _pause();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(fuzzy.rca);
        uint256 key = boundKey(fuzzy.unboundedSignerKey);
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, key);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, key);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    function test_Collect_Revert_WhenPaused(FuzzyTestAccept calldata fuzzy) public {
        // Accept first (before pausing)
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        _setGuardian(guardian, true);
        _pause();

        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, keccak256("col"), 1, 0));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Cancel_Revert_WhenPaused(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        _setGuardian(guardian, true);
        _pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rca.dataService);
        _recurringCollector.cancel(agreementId, IRecurringCollector.CancelAgreementBy.Payer);
    }

    function test_Update_Revert_WhenPaused(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            uint256 key,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        _setGuardian(guardian, true);
        _pause();

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );
        (, bytes memory updateSig) = _recurringCollectorHelper.generateSignedRCAU(rcau, key);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, updateSig);
    }

    // ==================== offer() during pause ====================

    /// @notice offer() is also guarded by whenNotPaused — it should revert while paused.
    function test_Offer_Revert_WhenPaused() public {
        _setGuardian(guardian, true);
        _pause();
        assertTrue(_recurringCollector.paused());

        MockAgreementOwner approver = new MockAgreementOwner();
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
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    /// @notice Offer stored before pause, then accept reverts during pause, then succeeds after unpause.
    function test_OfferBeforePause_AcceptAfterUnpause() public {
        MockAgreementOwner approver = new MockAgreementOwner();
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
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        // Store offer while unpaused
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        // Pause
        _setGuardian(guardian, true);
        _pause();

        // Accept reverts during pause
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");

        // Unpause
        vm.prank(guardian);
        _recurringCollector.unpause();

        // Accept succeeds after unpause (offer is still stored)
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(uint8(agreement.state), uint8(IRecurringCollector.AgreementState.Accepted));
    }

    /* solhint-enable graph/func-name-mixedcase */
}

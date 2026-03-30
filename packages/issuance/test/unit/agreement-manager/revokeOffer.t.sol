// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementManagerCancelOfferedTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_CancelOffered_ClearsAgreement() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);

        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim);

        bool gone = _cancelAgreement(agreementId);
        assertTrue(gone);

        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            0
        );
    }

    function test_CancelOffered_FullyRemovesTracking() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        _cancelAgreement(agreementId);

        // Agreement info should be zeroed out after cancel
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(
            IAgreementCollector(address(recurringCollector)),
            agreementId
        );
        assertEq(info.provider, address(0));
        assertEq(info.maxNextClaim, 0);
    }

    function test_CancelOffered_ClearsPendingUpdate() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Offer a pending update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau);

        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;
        // max(current, pending) = max(3700, 14600) = 14600
        uint256 pendingMaxClaim = 14600 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), pendingMaxClaim);

        _cancelAgreement(agreementId);

        // Both original and pending should be cleared
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_CancelOffered_EmitsEvent() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRemoved(agreementId);

        _cancelAgreement(agreementId);
    }

    function test_CancelOffered_RejectsUnknown_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));

        // cancelAgreement is a passthrough — unknown agreement triggers AgreementRejected via callback
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRejected(
            fakeId,
            address(recurringCollector),
            IRecurringAgreementManagement.AgreementRejectionReason.UnknownAgreement
        );

        vm.prank(operator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), fakeId, bytes32(0), 0);
    }

    function test_CancelOffered_Revert_WhenNotOperator() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        address nonOperator = makeAddr("nonOperator");
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonOperator,
                AGREEMENT_MANAGER_ROLE
            )
        );
        vm.prank(nonOperator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, activeHash, 0);
    }

    function test_CancelOffered_Succeeds_WhenPaused() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        vm.startPrank(governor);
        agreementManager.grantRole(keccak256("PAUSE_ROLE"), governor);
        agreementManager.pause();
        vm.stopPrank();

        // Role-gated functions should succeed even when paused
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(operator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, activeHash, 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

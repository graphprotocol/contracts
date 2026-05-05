// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IProviderEligibilityManagement } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibilityManagement.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockIssuanceAllocator } from "./mocks/MockIssuanceAllocator.sol";

contract RecurringAgreementManagerApproverTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- IAgreementOwner Tests --

    function test_ApproveAgreement_ReturnsSelector() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        _offerAgreement(rca);

        bytes32 agreementHash = recurringCollector.hashRCA(rca);
        bytes4 result = agreementManager.approveAgreement(agreementHash);
        assertEq(result, IAgreementOwner.approveAgreement.selector);
    }

    function test_ApproveAgreement_ReturnsZero_WhenNotAuthorized() public {
        bytes32 fakeHash = keccak256("fake agreement");
        assertEq(agreementManager.approveAgreement(fakeHash), bytes4(0));
    }

    function test_ApproveAgreement_DifferentHashesAreIndependent() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        // Only offer rca1
        _offerAgreement(rca1);

        // rca1 hash should be authorized
        bytes32 hash1 = recurringCollector.hashRCA(rca1);
        assertEq(agreementManager.approveAgreement(hash1), IAgreementOwner.approveAgreement.selector);

        // rca2 hash should NOT be authorized
        bytes32 hash2 = recurringCollector.hashRCA(rca2);
        assertEq(agreementManager.approveAgreement(hash2), bytes4(0));
    }

    // -- ERC165 Tests --

    function test_SupportsInterface_IIssuanceTarget() public view {
        assertTrue(agreementManager.supportsInterface(type(IIssuanceTarget).interfaceId));
    }

    function test_SupportsInterface_IAgreementOwner() public view {
        assertTrue(agreementManager.supportsInterface(type(IAgreementOwner).interfaceId));
    }

    function test_SupportsInterface_IRecurringAgreementManagement() public view {
        assertTrue(agreementManager.supportsInterface(type(IRecurringAgreementManagement).interfaceId));
    }

    function test_SupportsInterface_IRecurringEscrowManagement() public view {
        assertTrue(agreementManager.supportsInterface(type(IRecurringEscrowManagement).interfaceId));
    }

    function test_SupportsInterface_IProviderEligibilityManagement() public view {
        assertTrue(agreementManager.supportsInterface(type(IProviderEligibilityManagement).interfaceId));
    }

    function test_SupportsInterface_IRecurringAgreements() public view {
        assertTrue(agreementManager.supportsInterface(type(IRecurringAgreements).interfaceId));
    }

    // -- IIssuanceTarget Tests --

    function test_BeforeIssuanceAllocationChange_DoesNotRevert() public {
        agreementManager.beforeIssuanceAllocationChange();
    }

    function test_SetIssuanceAllocator_OnlyGovernor() public {
        address nonGovernor = makeAddr("nonGovernor");
        MockIssuanceAllocator alloc = new MockIssuanceAllocator(token, address(agreementManager));
        vm.expectRevert();
        vm.prank(nonGovernor);
        agreementManager.setIssuanceAllocator(address(alloc));
    }

    function test_SetIssuanceAllocator_Governor() public {
        MockIssuanceAllocator alloc = new MockIssuanceAllocator(token, address(agreementManager));
        vm.prank(governor);
        agreementManager.setIssuanceAllocator(address(alloc));
    }

    // -- View Function Tests --

    function test_GetDeficit_ZeroWhenFullyFunded() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        _offerAgreement(rca);

        // Fully funded (offerAgreement mints enough tokens)
        IPaymentsEscrow.EscrowAccount memory account = agreementManager.getEscrowAccount(_collector(), indexer);
        assertEq(account.balance - account.tokensThawing, agreementManager.getSumMaxNextClaim(_collector(), indexer));
    }

    function test_GetEscrowAccount_MatchesUnderlying() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        uint256 available = 500 ether;

        token.mint(address(agreementManager), available);
        vm.prank(operator);
        agreementManager.offerAgreement(rca, _collector());

        IPaymentsEscrow.EscrowAccount memory expected;
        (expected.balance, expected.tokensThawing, expected.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        IPaymentsEscrow.EscrowAccount memory actual = agreementManager.getEscrowAccount(_collector(), indexer);
        assertEq(actual.balance, expected.balance);
        assertEq(actual.tokensThawing, expected.tokensThawing);
        assertEq(actual.thawEndTimestamp, expected.thawEndTimestamp);
    }

    function test_GetRequiredEscrow_ZeroForUnknownIndexer() public {
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), makeAddr("unknown")), 0);
    }

    function test_GetAgreementMaxNextClaim_ZeroForUnknown() public view {
        assertEq(agreementManager.getAgreementMaxNextClaim(bytes16(keccak256("unknown"))), 0);
    }

    function test_GetIndexerAgreementCount_ZeroForUnknown() public {
        assertEq(agreementManager.getProviderAgreementCount(makeAddr("unknown")), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IProviderEligibilityManagement } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibilityManagement.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockIssuanceAllocator } from "./mocks/MockIssuanceAllocator.sol";

contract RecurringAgreementManagerApproverTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

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
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));

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
        assertEq(
            agreementManager.getAgreementMaxNextClaim(address(recurringCollector), bytes16(keccak256("unknown"))),
            0
        );
    }

    function test_GetIndexerAgreementCount_ZeroForUnknown() public {
        assertEq(agreementManager.getPairAgreementCount(address(recurringCollector), makeAddr("unknown")), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IContractApprover } from "@graphprotocol/interfaces/contracts/horizon/IContractApprover.sol";
import { IServiceAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IServiceAgreementManager.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { ServiceAgreementManagerSharedTest } from "./shared.t.sol";

contract ServiceAgreementManagerApproverTest is ServiceAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- IContractApprover Tests --

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
        assertEq(result, IContractApprover.approveAgreement.selector);
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
        assertEq(agreementManager.approveAgreement(hash1), IContractApprover.approveAgreement.selector);

        // rca2 hash should NOT be authorized
        bytes32 hash2 = recurringCollector.hashRCA(rca2);
        assertEq(agreementManager.approveAgreement(hash2), bytes4(0));
    }

    // -- ERC165 Tests --

    function test_SupportsInterface_IIssuanceTarget() public view {
        assertTrue(agreementManager.supportsInterface(type(IIssuanceTarget).interfaceId));
    }

    function test_SupportsInterface_IContractApprover() public view {
        assertTrue(agreementManager.supportsInterface(type(IContractApprover).interfaceId));
    }

    function test_SupportsInterface_IServiceAgreementManager() public view {
        assertTrue(agreementManager.supportsInterface(type(IServiceAgreementManager).interfaceId));
    }

    // -- IIssuanceTarget Tests --

    function test_BeforeIssuanceAllocationChange_DoesNotRevert() public {
        agreementManager.beforeIssuanceAllocationChange();
    }

    function test_SetIssuanceAllocator_OnlyGovernor() public {
        address nonGovernor = makeAddr("nonGovernor");
        vm.expectRevert();
        vm.prank(nonGovernor);
        agreementManager.setIssuanceAllocator(makeAddr("allocator"));
    }

    function test_SetIssuanceAllocator_Governor() public {
        vm.prank(governor);
        agreementManager.setIssuanceAllocator(makeAddr("allocator"));
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
        assertEq(agreementManager.getDeficit(indexer), 0);
    }

    function test_GetDeficit_ReturnsDeficitWhenUnderfunded() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        uint256 available = 500 ether;

        token.mint(address(agreementManager), available);
        vm.prank(operator);
        agreementManager.offerAgreement(rca);

        assertEq(agreementManager.getDeficit(indexer), maxClaim - available);
    }

    function test_GetRequiredEscrow_ZeroForUnknownIndexer() public {
        assertEq(agreementManager.getRequiredEscrow(makeAddr("unknown")), 0);
    }

    function test_GetAgreementMaxNextClaim_ZeroForUnknown() public view {
        assertEq(agreementManager.getAgreementMaxNextClaim(bytes16(keccak256("unknown"))), 0);
    }

    function test_GetIndexerAgreementCount_ZeroForUnknown() public {
        assertEq(agreementManager.getProviderAgreementCount(makeAddr("unknown")), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

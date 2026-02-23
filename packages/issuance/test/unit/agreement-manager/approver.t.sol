// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IContractApprover } from "@graphprotocol/interfaces/contracts/horizon/IContractApprover.sol";
import { IIndexingAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIndexingAgreementManager.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { IndexingAgreementManagerSharedTest } from "./shared.t.sol";

contract IndexingAgreementManagerApproverTest is IndexingAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- IContractApprover Tests --

    function test_IsAuthorizedAgreement_ReturnsSelector() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        _offerAgreement(rca);

        bytes32 agreementHash = recurringCollector.hashRCA(rca);
        bytes4 result = agreementManager.isAuthorizedAgreement(agreementHash);
        assertEq(result, IContractApprover.isAuthorizedAgreement.selector);
    }

    function test_IsAuthorizedAgreement_Revert_WhenNotAuthorized() public {
        bytes32 fakeHash = keccak256("fake agreement");

        vm.expectRevert(
            abi.encodeWithSelector(
                IIndexingAgreementManager.IndexingAgreementManagerAgreementNotAuthorized.selector,
                fakeHash
            )
        );
        agreementManager.isAuthorizedAgreement(fakeHash);
    }

    function test_IsAuthorizedAgreement_DifferentHashesAreIndependent() public {
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
        assertEq(agreementManager.isAuthorizedAgreement(hash1), IContractApprover.isAuthorizedAgreement.selector);

        // rca2 hash should NOT be authorized
        bytes32 hash2 = recurringCollector.hashRCA(rca2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IIndexingAgreementManager.IndexingAgreementManagerAgreementNotAuthorized.selector,
                hash2
            )
        );
        agreementManager.isAuthorizedAgreement(hash2);
    }

    // -- ERC165 Tests --

    function test_SupportsInterface_IIssuanceTarget() public view {
        assertTrue(agreementManager.supportsInterface(type(IIssuanceTarget).interfaceId));
    }

    function test_SupportsInterface_IContractApprover() public view {
        assertTrue(agreementManager.supportsInterface(type(IContractApprover).interfaceId));
    }

    function test_SupportsInterface_IIndexingAgreementManager() public view {
        assertTrue(agreementManager.supportsInterface(type(IIndexingAgreementManager).interfaceId));
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
        assertEq(agreementManager.getIndexerAgreementCount(makeAddr("unknown")), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

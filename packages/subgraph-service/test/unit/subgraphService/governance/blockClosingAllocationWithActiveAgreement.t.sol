// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SubgraphServiceGovernanceBlockClosingAllocationTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_Governance_SetBlockClosingAllocationWithActiveAgreement_Enable() public useGovernor {
        // Default is false
        assertFalse(subgraphService.getBlockClosingAllocationWithActiveAgreement());

        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.BlockClosingAllocationWithActiveAgreementSet(true);
        subgraphService.setBlockClosingAllocationWithActiveAgreement(true);

        assertTrue(subgraphService.getBlockClosingAllocationWithActiveAgreement());
    }

    function test_Governance_SetBlockClosingAllocationWithActiveAgreement_Disable() public useGovernor {
        // Enable first
        subgraphService.setBlockClosingAllocationWithActiveAgreement(true);
        assertTrue(subgraphService.getBlockClosingAllocationWithActiveAgreement());

        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.BlockClosingAllocationWithActiveAgreementSet(false);
        subgraphService.setBlockClosingAllocationWithActiveAgreement(false);

        assertFalse(subgraphService.getBlockClosingAllocationWithActiveAgreement());
    }

    function test_Governance_SetBlockClosingAllocationWithActiveAgreement_NoopWhenSameValue() public useGovernor {
        // Default is false — setting false again should be a noop (no event)
        vm.recordLogs();
        subgraphService.setBlockClosingAllocationWithActiveAgreement(false);
        assertEq(vm.getRecordedLogs().length, 0, "should not emit when value unchanged");

        // Enable, then set true again — noop
        subgraphService.setBlockClosingAllocationWithActiveAgreement(true);
        vm.recordLogs();
        subgraphService.setBlockClosingAllocationWithActiveAgreement(true);
        assertEq(vm.getRecordedLogs().length, 0, "should not emit when value unchanged (true)");
    }

    function test_Governance_SetBlockClosingAllocationWithActiveAgreement_RevertWhen_NotGovernor() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setBlockClosingAllocationWithActiveAgreement(true);
    }
}

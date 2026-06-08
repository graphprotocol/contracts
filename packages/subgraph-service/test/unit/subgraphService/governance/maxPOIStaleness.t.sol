// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AllocationHandler } from "../../../../contracts/libraries/AllocationHandler.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SubgraphServiceGovernanceMaxPOIStalenessTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_Governance_SetMaxPOIStaleness(uint256 maxPOIStaleness) public useGovernor {
        vm.expectEmit(address(subgraphService));
        emit AllocationHandler.MaxPOIStalenessSet(maxPOIStaleness);
        subgraphService.setMaxPOIStaleness(maxPOIStaleness);

        assertEq(subgraphService.maxPOIStaleness(), maxPOIStaleness);
    }

    function test_Governance_SetMaxPOIStaleness_RevertWhen_NotGovernor() public useIndexer {
        uint256 maxPOIStaleness = 14 days;
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setMaxPOIStaleness(maxPOIStaleness);
    }
}

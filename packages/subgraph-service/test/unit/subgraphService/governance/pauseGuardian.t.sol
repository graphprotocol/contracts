// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IDataServicePausable } from "@graphprotocol/interfaces/contracts/data-service/IDataServicePausable.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SubgraphServiceGovernancePauseGuardianTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_Governance_SetPauseGuardian() public useGovernor {
        // users.pauseGuardian is already set in setUp, use a new address
        address newGuardian = createUser("newPauseGuardian");

        vm.expectEmit(address(subgraphService));
        emit IDataServicePausable.PauseGuardianSet(newGuardian, true);
        subgraphService.setPauseGuardian(newGuardian, true);

        assertTrue(subgraphService.pauseGuardians(newGuardian));
    }

    function test_Governance_SetPauseGuardian_Remove() public useGovernor {
        // users.pauseGuardian is already set to true in setUp
        vm.expectEmit(address(subgraphService));
        emit IDataServicePausable.PauseGuardianSet(users.pauseGuardian, false);
        subgraphService.setPauseGuardian(users.pauseGuardian, false);

        assertFalse(subgraphService.pauseGuardians(users.pauseGuardian));
    }

    function test_Governance_SetPauseGuardian_RevertWhen_NoChange() public useGovernor {
        // users.pauseGuardian is already set to true in setUp
        vm.expectRevert(
            abi.encodeWithSelector(
                IDataServicePausable.DataServicePausablePauseGuardianNoChange.selector,
                users.pauseGuardian,
                true
            )
        );
        subgraphService.setPauseGuardian(users.pauseGuardian, true);
    }

    function test_Governance_SetPauseGuardian_RevertWhen_NotGovernor() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setPauseGuardian(users.pauseGuardian, true);
    }
}

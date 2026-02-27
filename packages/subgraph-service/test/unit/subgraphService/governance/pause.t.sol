// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IDataServicePausable } from "@graphprotocol/interfaces/contracts/data-service/IDataServicePausable.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceGovernancePauseTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_Governance_Pause() public {
        resetPrank(users.pauseGuardian);

        vm.expectEmit(address(subgraphService));
        emit PausableUpgradeable.Paused(users.pauseGuardian);
        subgraphService.pause();

        assertTrue(subgraphService.paused());
    }

    function test_Governance_Unpause() public {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectEmit(address(subgraphService));
        emit PausableUpgradeable.Unpaused(users.pauseGuardian);
        subgraphService.unpause();

        assertFalse(subgraphService.paused());
    }

    function test_Governance_Pause_RevertWhen_NotPauseGuardian() public useIndexer {
        vm.expectRevert(
            abi.encodeWithSelector(IDataServicePausable.DataServicePausableNotPauseGuardian.selector, users.indexer)
        );
        subgraphService.pause();
    }

    function test_Governance_Unpause_RevertWhen_NotPauseGuardian() public {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(users.indexer);
        vm.expectRevert(
            abi.encodeWithSelector(IDataServicePausable.DataServicePausableNotPauseGuardian.selector, users.indexer)
        );
        subgraphService.unpause();
    }

    function test_Governance_Pause_RevertWhen_AlreadyPaused() public {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        subgraphService.pause();
    }

    function test_Governance_Unpause_RevertWhen_NotPaused() public {
        resetPrank(users.pauseGuardian);

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.ExpectedPause.selector));
        subgraphService.unpause();
    }
}

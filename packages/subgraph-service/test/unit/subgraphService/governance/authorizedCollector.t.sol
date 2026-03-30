// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAuthorizedCollectorTest is SubgraphServiceTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_SetAuthorizedCollector() public {
        address collector = makeAddr("newCollector");
        assertFalse(subgraphService.isAuthorizedCollector(collector));

        resetPrank(users.governor);
        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.AuthorizedCollectorSet(collector, true);
        subgraphService.setAuthorizedCollector(collector, true);

        assertTrue(subgraphService.isAuthorizedCollector(collector));
    }

    function test_SetAuthorizedCollector_Remove() public {
        // RC was authorized in setup
        assertTrue(subgraphService.isAuthorizedCollector(address(recurringCollector)));

        resetPrank(users.governor);
        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.AuthorizedCollectorSet(address(recurringCollector), false);
        subgraphService.setAuthorizedCollector(address(recurringCollector), false);

        assertFalse(subgraphService.isAuthorizedCollector(address(recurringCollector)));
    }

    function test_SetAuthorizedCollector_Idempotent() public {
        assertTrue(subgraphService.isAuthorizedCollector(address(recurringCollector)));

        resetPrank(users.governor);
        // Setting same value should not emit
        vm.recordLogs();
        subgraphService.setAuthorizedCollector(address(recurringCollector), true);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_SetAuthorizedCollector_RevertWhen_NotOwner() public {
        address collector = makeAddr("newCollector");

        resetPrank(users.indexer);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setAuthorizedCollector(collector, true);
    }

    function test_SetAuthorizedCollector_RevertWhen_ZeroAddress() public {
        resetPrank(users.governor);
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceNotCollector.selector, address(0)));
        subgraphService.setAuthorizedCollector(address(0), true);
    }
}

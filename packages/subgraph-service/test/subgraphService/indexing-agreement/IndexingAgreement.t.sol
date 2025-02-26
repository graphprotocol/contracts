// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IIPCollector } from "@graphprotocol/horizon/contracts/interfaces/IIPCollector.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceIndexingAgreementTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_AcceptIAV_Revert_WhenPaused(
        address allocationId,
        address rando,
        IIPCollector.SignedIAV calldata signedIAV
    ) public {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(rando);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.acceptIAV(allocationId, signedIAV);
    }
}

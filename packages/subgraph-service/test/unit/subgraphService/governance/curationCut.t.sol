// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
contract SubgraphServiceGovernanceCurationCutTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_Governance_SetCurationCut(uint256 curationCut) public useGovernor {
        vm.assume(curationCut <= MAX_PPM);

        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.CurationCutSet(curationCut);
        subgraphService.setCurationCut(curationCut);

        assertEq(subgraphService.curationFeesCut(), curationCut);
    }

    function test_Governance_SetCurationCut_RevertWhen_InvalidPPM(uint256 curationCut) public useGovernor {
        vm.assume(curationCut > MAX_PPM);

        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidCurationCut.selector, curationCut)
        );
        subgraphService.setCurationCut(curationCut);
    }

    function test_Governance_SetCurationCut_RevertWhen_NotGovernor() public useIndexer {
        uint256 curationCut = 100_000; // 10%
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setCurationCut(curationCut);
    }
}

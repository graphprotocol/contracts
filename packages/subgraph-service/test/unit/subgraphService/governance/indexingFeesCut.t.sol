// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SubgraphServiceGovernanceIndexingFeesCutTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_Governance_SetIndexingFeesCut(uint256 indexingFeesCut) public useGovernor {
        vm.assume(indexingFeesCut <= MAX_PPM);

        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.IndexingFeesCutSet(indexingFeesCut);
        subgraphService.setIndexingFeesCut(indexingFeesCut);

        assertEq(subgraphService.indexingFeesCut(), indexingFeesCut);
    }

    function test_Governance_SetIndexingFeesCut_RevertWhen_InvalidPPM(uint256 indexingFeesCut) public useGovernor {
        vm.assume(indexingFeesCut > MAX_PPM);

        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidIndexingFeesCut.selector, indexingFeesCut)
        );
        subgraphService.setIndexingFeesCut(indexingFeesCut);
    }

    function test_Governance_SetIndexingFeesCut_RevertWhen_NotGovernor() public useIndexer {
        uint256 indexingFeesCut = 100_000; // 10%
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setIndexingFeesCut(indexingFeesCut);
    }
}

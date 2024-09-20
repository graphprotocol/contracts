// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DisputeManagerGovernanceArbitratorTest is SubgraphServiceTest {

    /**
     * ACTIONS
     */

    function _setStakeToFeesRatio(uint256 _stakeToFeesRatio) internal {
        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.StakeToFeesRatioSet(_stakeToFeesRatio);
        subgraphService.setStakeToFeesRatio(_stakeToFeesRatio);
        assertEq(subgraphService.stakeToFeesRatio(), _stakeToFeesRatio);
    }

    /*
     * TESTS
     */

    function test_Governance_SetStakeToFeesRatio(uint256 stakeToFeesRatio) public useGovernor {
        vm.assume(stakeToFeesRatio > 0);
        _setStakeToFeesRatio(stakeToFeesRatio);
    }

    function test_Governance_RevertWhen_ZeroValue() public useGovernor {
        uint256 stakeToFeesRatio = 0;
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidZeroStakeToFeesRatio.selector));
        subgraphService.setStakeToFeesRatio(stakeToFeesRatio);
    }

    function test_Governance_RevertWhen_NotGovernor() public useIndexer {
        uint256 stakeToFeesRatio = 2;
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setStakeToFeesRatio(stakeToFeesRatio);
    }
}

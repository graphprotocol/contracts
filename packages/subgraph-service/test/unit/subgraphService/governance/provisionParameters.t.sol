// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IProvisionManager } from "@graphprotocol/interfaces/contracts/toolshed/internal/IProvisionManager.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SubgraphServiceGovernanceProvisionParametersTest is SubgraphServiceTest {
    /*
     * TESTS - setMinimumProvisionTokens
     */

    function test_Governance_SetMinimumProvisionTokens(uint256 minimumProvisionTokens) public useGovernor {
        vm.expectEmit(address(subgraphService));
        emit IProvisionManager.ProvisionTokensRangeSet(minimumProvisionTokens, type(uint256).max);
        subgraphService.setMinimumProvisionTokens(minimumProvisionTokens);

        (uint256 min, uint256 max) = subgraphService.getProvisionTokensRange();
        assertEq(min, minimumProvisionTokens);
        assertEq(max, type(uint256).max);
    }

    function test_Governance_SetMinimumProvisionTokens_RevertWhen_NotGovernor() public useIndexer {
        uint256 minimumProvisionTokens = 1000 ether;
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setMinimumProvisionTokens(minimumProvisionTokens);
    }

    /*
     * TESTS - setDelegationRatio
     */

    function test_Governance_SetDelegationRatio(uint32 delegationRatio) public useGovernor {
        vm.expectEmit(address(subgraphService));
        emit IProvisionManager.DelegationRatioSet(delegationRatio);
        subgraphService.setDelegationRatio(delegationRatio);

        assertEq(subgraphService.getDelegationRatio(), delegationRatio);
    }

    function test_Governance_SetDelegationRatio_RevertWhen_NotGovernor() public useIndexer {
        uint32 delegationRatio = 16;
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setDelegationRatio(delegationRatio);
    }
}

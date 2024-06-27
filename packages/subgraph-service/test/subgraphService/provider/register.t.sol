// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceRegisterTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function testRegister_Indexer(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        _createProvision(tokens);
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        vm.expectEmit(address(subgraphService));
        emit IDataService.ServiceProviderRegistered(
            users.indexer,
            data
        );
        subgraphService.register(users.indexer, data);

        uint256 registeredAt;
        string memory url;
        string memory geoHash;
        (registeredAt, url, geoHash) = subgraphService.indexers(users.indexer);
        assertEq(registeredAt, block.timestamp);
        assertEq(url, "url");
        assertEq(geoHash, "geoHash");
    }

    function testRegister_RevertIf_AlreadyRegistered(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceIndexerAlreadyRegistered.selector));
        _registerIndexer(users.rewardsDestination);
    }

    function testRegister_RevertWhen_InvalidProvision() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerProvisionNotFound.selector,
            users.indexer
        ));
        _registerIndexer(users.rewardsDestination);
    }

    function testRegister_RevertWhen_NotAuthorized() public {
        resetPrank(users.operator);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            users.operator,
            users.indexer
        ));
        _registerIndexer(users.rewardsDestination);
    }

    function testRegister_RevertWhen_InvalidProvisionValues(uint256 tokens) public useIndexer {
        tokens = bound(tokens, 1, minimumProvisionTokens - 1);
        _createProvision(tokens);

        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector, 
            "tokens",
            tokens,
            minimumProvisionTokens,
            maximumProvisionTokens
        ));
        _registerIndexer(address(0));
    }
}

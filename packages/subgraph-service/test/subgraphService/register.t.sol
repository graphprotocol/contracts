// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ISubgraphService } from "../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "./SubgraphService.t.sol";

contract SubgraphServiceRegisterTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function testRegister_Indexer(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, 10_000_000_000 ether);
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
    ) public useIndexer useProvision(tokens) {
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceIndexerAlreadyRegistered.selector));
        subgraphService.register(users.indexer, data);
    }

    function testRegister_RevertWhen_InvalidProvision() public useIndexer {
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerProvisionNotFound.selector,
            users.indexer
        ));
        subgraphService.register(users.indexer, data);
    }
}

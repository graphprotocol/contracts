// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceProviderRegisterTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Provider_Register(uint256 tokens) public useIndexer {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        _register(users.indexer, data);
    }

    function test_SubgraphService_Provider_Register_MultipleTimes(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        _register(users.indexer, data);

        bytes memory data2 = abi.encode("url2", "geoHash2", users.rewardsDestination);
        _register(users.indexer, data2);

        (string memory url, string memory geoHash) = subgraphService.indexers(users.indexer);
        assertEq(url, "url2");
        assertEq(geoHash, "geoHash2");
    }

    function test_SubgraphService_Provider_Register_RevertWhen_InvalidProvision() public useIndexer {
        vm.expectRevert(
            abi.encodeWithSelector(ProvisionManager.ProvisionManagerProvisionNotFound.selector, users.indexer)
        );
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        subgraphService.register(users.indexer, data);
    }

    function test_SubgraphService_Provider_Register_RevertWhen_NotAuthorized() public {
        resetPrank(users.operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerNotAuthorized.selector,
                users.indexer,
                users.operator
            )
        );
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        subgraphService.register(users.indexer, data);
    }

    function test_SubgraphService_Provider_Register_RevertWhen_InvalidProvisionValues(
        uint256 tokens
    ) public useIndexer {
        tokens = bound(tokens, 1, MINIMUM_PROVISION_TOKENS - 1);
        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);

        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerInvalidValue.selector,
                "tokens",
                tokens,
                MINIMUM_PROVISION_TOKENS,
                MAXIMUM_PROVISION_TOKENS
            )
        );
        subgraphService.register(users.indexer, abi.encode("url", "geoHash", address(0)));
    }

    function test_SubgraphService_Provider_Register_RevertIf_EmptyUrl(uint256 tokens) public useIndexer {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        bytes memory data = abi.encode("", "geoHash", users.rewardsDestination);
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceEmptyUrl.selector));
        subgraphService.register(users.indexer, data);
    }

    function test_SubgraphService_Provider_Register_RevertIf_EmptyGeohash(uint256 tokens) public useIndexer {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        bytes memory data = abi.encode("url", "", users.rewardsDestination);
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceEmptyGeohash.selector));
        subgraphService.register(users.indexer, data);
    }
}

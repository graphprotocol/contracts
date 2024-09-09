// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceProviderRegisterTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function test_SubgraphService_Provider_Register(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        _register(users.indexer, data);
    }

    function test_SubgraphService_Provider_Register_RevertIf_AlreadyRegistered(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceIndexerAlreadyRegistered.selector));
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        subgraphService.register(users.indexer, data);
    }

    function test_SubgraphService_Provider_Register_RevertWhen_InvalidProvision() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerProvisionNotFound.selector,
            users.indexer
        ));
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        subgraphService.register(users.indexer, data);
    }

    function test_SubgraphService_Provider_Register_RevertWhen_NotAuthorized() public {
        resetPrank(users.operator);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            users.operator,
            users.indexer
        ));
        bytes memory data = abi.encode("url", "geoHash", users.rewardsDestination);
        subgraphService.register(users.indexer, data);
    }

    function test_SubgraphService_Provider_Register_RevertWhen_InvalidProvisionValues(uint256 tokens) public useIndexer {
        tokens = bound(tokens, 1, minimumProvisionTokens - 1);
        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);

        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector, 
            "tokens",
            tokens,
            minimumProvisionTokens,
            maximumProvisionTokens
        ));
        subgraphService.register(users.indexer, abi.encode("url", "geoHash", address(0)));
    }

    function test_SubgraphService_Provider_Register_RevertIf_EmptyUrl(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        bytes memory data = abi.encode("", "geoHash", users.rewardsDestination);
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceEmptyUrl.selector));
        subgraphService.register(users.indexer, data);
    }

    function test_SubgraphService_Provider_Register_RevertIf_EmptyGeohash(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        bytes memory data = abi.encode("url", "", users.rewardsDestination);
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceEmptyGeohash.selector));
        subgraphService.register(users.indexer, data);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceProvisionAcceptTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function test_SubgraphService_Provision_Accept(
        uint256 tokens,
        uint32 newVerifierCut,
        uint64 newDisputePeriod
    ) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        vm.assume(newVerifierCut >= fishermanRewardPercentage);
        vm.assume(newVerifierCut <= MAX_PPM);
        vm.assume(newDisputePeriod >= disputePeriod);

        // Setup indexer
        _createProvision(users.indexer, tokens, fishermanRewardPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        // Update parameters with new values
        _setProvisionParameters(users.indexer, address(subgraphService), newVerifierCut, newDisputePeriod);

        // Accept provision and check parameters
        _acceptProvision(users.indexer, "");
    }

    function test_SubgraphService_Provision_Accept_RevertWhen_NotRegistered() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            users.indexer
        ));
        subgraphService.acceptProvision(users.indexer, "");
    }

    function test_SubgraphService_Provision_Accept_RevertWhen_NotAuthorized() public {
        resetPrank(users.operator);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            users.operator,
            users.indexer
        ));
        subgraphService.acceptProvision(users.indexer, "");
    }

    function test_SubgraphService_Provision_Accept_RevertIf_InvalidVerifierCut(
        uint256 tokens,
        uint32 newVerifierCut
    ) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        vm.assume(newVerifierCut > MAX_PPM);

        // Setup indexer
        _createProvision(users.indexer, tokens, fishermanRewardPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        // Update parameters with new values
        _setProvisionParameters(users.indexer, address(subgraphService), newVerifierCut, disputePeriod);

        // Should revert since newVerifierCut is invalid
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "maxVerifierCut",
            newVerifierCut,
            fishermanRewardPercentage,
            MAX_PPM
        ));
        subgraphService.acceptProvision(users.indexer, "");
    }

    function test_SubgraphService_Provision_Accept_RevertIf_InvalidDisputePeriod(
        uint256 tokens,
        uint64 newDisputePeriod
    ) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        vm.assume(newDisputePeriod < disputePeriod);

        // Setup indexer
        _createProvision(users.indexer, tokens, fishermanRewardPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        // Update parameters with new values
        _setProvisionParameters(users.indexer, address(subgraphService), fishermanRewardPercentage, newDisputePeriod);

        // Should revert since newDisputePeriod is invalid
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "thawingPeriod",
            newDisputePeriod,
            disputePeriod,
            type(uint64).max
        ));
        subgraphService.acceptProvision(users.indexer, "");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceProvisionAcceptTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Provision_Accept(
        uint256 tokens,
        uint32 newVerifierCut,
        uint64 newDisputePeriod
    ) public {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        vm.assume(newVerifierCut >= FISHERMAN_REWARD_PERCENTAGE);
        vm.assume(newVerifierCut <= MAX_PPM);
        newDisputePeriod = uint64(bound(newDisputePeriod, 1, MAX_WAIT_PERIOD));

        // Set the dispute period to the new value
        resetPrank(users.governor);
        disputeManager.setDisputePeriod(newDisputePeriod);

        // Setup indexer
        resetPrank(users.indexer);
        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, newDisputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        // Update parameters with new values
        _setProvisionParameters(users.indexer, address(subgraphService), newVerifierCut, newDisputePeriod);

        // Accept provision and check parameters
        _acceptProvision(users.indexer, "");
    }

    function test_SubgraphService_Provision_Accept_When_NotRegistered(
        uint256 tokens,
        uint32 newVerifierCut,
        uint64 newDisputePeriod
    ) public {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        vm.assume(newVerifierCut >= FISHERMAN_REWARD_PERCENTAGE);
        vm.assume(newVerifierCut <= MAX_PPM);
        newDisputePeriod = uint64(bound(newDisputePeriod, 1, MAX_WAIT_PERIOD));

        // Set the dispute period to the new value
        resetPrank(users.governor);
        disputeManager.setDisputePeriod(newDisputePeriod);

        // Setup indexer but dont register
        resetPrank(users.indexer);
        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, newDisputePeriod);

        // Update parameters with new values
        _setProvisionParameters(users.indexer, address(subgraphService), newVerifierCut, newDisputePeriod);

        // Accept provision and check parameters
        _acceptProvision(users.indexer, "");
    }

    function test_SubgraphService_Provision_Accept_RevertWhen_NotAuthorized() public {
        resetPrank(users.operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerNotAuthorized.selector,
                users.indexer,
                users.operator
            )
        );
        subgraphService.acceptProvisionPendingParameters(users.indexer, "");
    }

    function test_SubgraphService_Provision_Accept_RevertIf_InvalidVerifierCut(
        uint256 tokens,
        uint32 newVerifierCut
    ) public useIndexer {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        vm.assume(newVerifierCut < FISHERMAN_REWARD_PERCENTAGE);

        // Setup indexer
        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        // Update parameters with new values
        _setProvisionParameters(users.indexer, address(subgraphService), newVerifierCut, DISPUTE_PERIOD);

        // Should revert since newVerifierCut is invalid
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerInvalidValue.selector,
                "maxVerifierCut",
                newVerifierCut,
                FISHERMAN_REWARD_PERCENTAGE,
                MAX_PPM
            )
        );
        subgraphService.acceptProvisionPendingParameters(users.indexer, "");
    }

    function test_SubgraphService_Provision_Accept_RevertIf_InvalidDisputePeriod(
        uint256 tokens,
        uint64 newDisputePeriod
    ) public useIndexer {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        vm.assume(newDisputePeriod < DISPUTE_PERIOD);

        // Setup indexer
        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        // Update parameters with new values
        _setProvisionParameters(users.indexer, address(subgraphService), FISHERMAN_REWARD_PERCENTAGE, newDisputePeriod);

        // Should revert since newDisputePeriod is invalid
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerInvalidValue.selector,
                "thawingPeriod",
                newDisputePeriod,
                DISPUTE_PERIOD,
                DISPUTE_PERIOD
            )
        );
        subgraphService.acceptProvisionPendingParameters(users.indexer, "");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IIPCollector } from "@graphprotocol/horizon/contracts/interfaces/IIPCollector.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceIndexingAgreementTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_AcceptIAV_Revert_WhenPaused(
        address allocationId,
        address rando,
        IIPCollector.SignedIAV calldata signedIAV
    ) public {
        vm.assume(_notInUsers(rando));

        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(rando);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.acceptIAV(allocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenNotAuthorized(
        address allocationId,
        address rando,
        IIPCollector.SignedIAV calldata signedIAV
    ) public {
        vm.assume(_notInUsers(rando));
        resetPrank(rando);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            signedIAV.iav.serviceProvider,
            rando
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIAV(allocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenInvalidProvision(
        uint256 tokens,
        address allocationId,
        IIPCollector.SignedIAV memory signedIAV
    ) public useIndexer {
        tokens = bound(tokens, 1, minimumProvisionTokens - 1);
        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);

        signedIAV.iav.serviceProvider = users.indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "tokens",
            tokens,
            minimumProvisionTokens,
            maximumProvisionTokens
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIAV(allocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenIndexerNotRegistered(
        uint256 tokens,
        address allocationId,
        IIPCollector.SignedIAV memory signedIAV
    ) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        signedIAV.iav.serviceProvider = users.indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            users.indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIAV(allocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenNotDataService(
        uint256 tokens,
        address allocationId,
        IIPCollector.SignedIAV memory signedIAV
    ) public useIndexer useAllocation(tokens) {
        signedIAV.iav.serviceProvider = users.indexer;
        // bytes memory expectedErr = abi.encodeWithSelector(
        //     ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
        //     users.indexer
        // );
        vm.expectRevert("SubgraphService: Data service mismatch");
        subgraphService.acceptIAV(allocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenInvalidMetadata(
        uint256 tokens,
        address allocationId,
        IIPCollector.SignedIAV memory signedIAV
    ) public useIndexer useAllocation(tokens) {
        signedIAV.iav.serviceProvider = users.indexer;
        signedIAV.iav.dataService = address(subgraphService);
        // bytes memory expectedErr = abi.encodeWithSelector(
        //     ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
        //     users.indexer
        // );
        vm.expectRevert("SubgraphService: Invalid IAV metadata");
        subgraphService.acceptIAV(allocationId, signedIAV);
    }

    function _notInUsers(address _candidate) private view returns (bool) {
        return
            _candidate != users.governor &&
            _candidate != users.deployer &&
            _candidate != users.indexer &&
            _candidate != users.operator &&
            _candidate != users.gateway &&
            _candidate != users.verifier &&
            _candidate != users.delegator &&
            _candidate != users.arbitrator &&
            _candidate != users.fisherman &&
            _candidate != users.rewardsDestination &&
            _candidate != users.pauseGuardian;
    }
}

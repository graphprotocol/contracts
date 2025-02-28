// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IIPCollector } from "@graphprotocol/horizon/contracts/interfaces/IIPCollector.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { Bounder } from "@graphprotocol/horizon/test/utils/Bounder.t.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceIndexingAgreementTest is SubgraphServiceTest, Bounder {
    /*
     * TESTS
     */

    function test_SubgraphService_AcceptIAV_Revert_WhenPaused(
        address allocationId,
        address rando,
        IIPCollector.SignedIAV calldata signedIAV
    ) public {
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
    ) public {
        resetPrank(users.indexer);
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
    ) public {
        resetPrank(users.indexer);
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
        setupFuzzyServiceProviderParams calldata _fuzzyParams,
        IIPCollector.SignedIAV memory signedIAV
    ) public {
        serviceProviderParams memory params = _setupFuzzyServiceProvider(_fuzzyParams);

        signedIAV.iav.serviceProvider = params.serviceProvider;
        // bytes memory expectedErr = abi.encodeWithSelector(
        //     ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
        //     users.indexer
        // );
        vm.expectRevert("SubgraphService: Data service mismatch");
        vm.startPrank(params.serviceProvider);
        subgraphService.acceptIAV(params.allocationId, signedIAV);
    }

    struct setupFuzzyServiceProviderParams {
        address serviceProvider;
        uint256 unboundedTokens;
        uint256 unboundedAllocationPrivateKey;
        bytes32 subgraphDeploymentId;
    }

    struct serviceProviderParams {
        address serviceProvider;
        address allocationId;
        bytes32 subgraphDeploymentId;
        uint256 tokens;
    }

    function _nicerResetPrank(address _addr) private returns (address) {
        address _originalPrankAddress = msg.sender;
        resetPrank(_addr);

        return _originalPrankAddress;
    }

    function _stopOrResetPrank(address _originalSender) private {
        if (_originalSender == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
            vm.stopPrank();
        } else {
            resetPrank(_originalSender);
        }
    }

    function _setupFuzzyServiceProvider(
        setupFuzzyServiceProviderParams calldata _params
    ) private returns (serviceProviderParams memory) {
        uint256 tokens = bound(_params.unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(_params.serviceProvider, tokens);
        (uint256 allocationKey, address allocationId) = boundKeyAndAddr(_params.unboundedAllocationPrivateKey);
        address originalPrank = _nicerResetPrank(_params.serviceProvider);
        _createProvision(_params.serviceProvider, tokens, maxSlashingPercentage, disputePeriod);
        _register(_params.serviceProvider, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            _params.serviceProvider,
            _params.subgraphDeploymentId,
            allocationKey,
            tokens
        );
        _startService(_params.serviceProvider, data);
        _stopOrResetPrank(originalPrank);

        return
            serviceProviderParams({
                serviceProvider: _params.serviceProvider,
                allocationId: allocationId,
                subgraphDeploymentId: _params.subgraphDeploymentId,
                tokens: tokens
            });
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

    function test_SubgraphService_AcceptIAV_Revert_WhenInvalidAllocation(
        uint256 tokens,
        address allocationId,
        IIPCollector.SignedIAV memory signedIAV
    ) public useIndexer useAllocation(tokens) {
        signedIAV.iav.serviceProvider = users.indexer;
        signedIAV.iav.dataService = address(subgraphService);
        signedIAV.iav.metadata = abi.encode(
            ISubgraphService.IndexingAgreementVoucherMetadata({
                tokensPerSecond: 0,
                tokensPerEntityPerSecond: 0,
                subgraphDeploymentId: "",
                protocolNetwork: "",
                chainId: ""
            })
        );
        bytes memory expectedErr = abi.encodeWithSelector(Allocation.AllocationDoesNotExist.selector, allocationId);
        vm.expectRevert(expectedErr);
        subgraphService.acceptIAV(allocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenServiceProviderMismatchAllocation(
        uint256 tokens,
        address serviceProvider,
        bytes32 _subgraphDeployment,
        IIPCollector.SignedIAV memory signedIAV
    ) public useIndexer useAllocation(tokens) {
        mint(serviceProvider, tokens);
        resetPrank(serviceProvider);
        _createProvision(serviceProvider, tokens, maxSlashingPercentage, disputePeriod);
        _register(serviceProvider, abi.encode("url", "geoHash", address(0)));
        (, uint256 _allocationIDPrivateKey) = makeAddrAndKey("allocationIdz");
        bytes memory data = _createSubgraphAllocationData(
            serviceProvider,
            _subgraphDeployment,
            _allocationIDPrivateKey,
            tokens
        );
        _startService(serviceProvider, data);
        signedIAV.iav.serviceProvider = serviceProvider;
        signedIAV.iav.dataService = address(subgraphService);
        signedIAV.iav.metadata = abi.encode(
            ISubgraphService.IndexingAgreementVoucherMetadata({
                tokensPerSecond: 0,
                tokensPerEntityPerSecond: 0,
                subgraphDeploymentId: "",
                protocolNetwork: "",
                chainId: ""
            })
        );
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceInvalidSomething.selector,
            signedIAV.iav.serviceProvider,
            users.indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIAV(allocationID, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenDeploymentIdMismatch(
        uint256 tokens,
        bytes32 subgraphDeploymentId,
        IIPCollector.SignedIAV memory signedIAV
    ) public useIndexer useAllocation(tokens) {
        signedIAV.iav.serviceProvider = users.indexer;
        signedIAV.iav.dataService = address(subgraphService);
        signedIAV.iav.metadata = abi.encode(
            ISubgraphService.IndexingAgreementVoucherMetadata({
                tokensPerSecond: 0,
                tokensPerEntityPerSecond: 0,
                subgraphDeploymentId: subgraphDeploymentId,
                protocolNetwork: "",
                chainId: ""
            })
        );
        vm.expectRevert("SubgraphService: SubgraphDeploymentId mismatch");
        subgraphService.acceptIAV(allocationID, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenAgreementAlreadyAccepted(
        uint256 tokens,
        IIPCollector.SignedIAV memory signedIAV
    ) public useIndexer useAllocation(tokens) {
        signedIAV.iav.serviceProvider = users.indexer;
        signedIAV.iav.dataService = address(subgraphService);
        signedIAV.iav.metadata = abi.encode(
            ISubgraphService.IndexingAgreementVoucherMetadata({
                tokensPerSecond: 0,
                tokensPerEntityPerSecond: 0,
                subgraphDeploymentId: subgraphDeployment,
                protocolNetwork: "",
                chainId: ""
            })
        );
        vm.mockCall(
            address(ipCollector),
            abi.encodeWithSelector(IIPCollector.accept.selector, signedIAV),
            new bytes(0)
        );
        subgraphService.acceptIAV(allocationID, signedIAV);

        vm.expectRevert("SubgraphService: Agreement already accepted");
        subgraphService.acceptIAV(allocationID, signedIAV);
    }

    function test_SubgraphService_AcceptIAV(
        uint256 tokens,
        IIPCollector.SignedIAV memory signedIAV
    ) public useIndexer useAllocation(tokens) {
        signedIAV.iav.serviceProvider = users.indexer;
        signedIAV.iav.dataService = address(subgraphService);
        signedIAV.iav.metadata = abi.encode(
            ISubgraphService.IndexingAgreementVoucherMetadata({
                tokensPerSecond: 0,
                tokensPerEntityPerSecond: 0,
                subgraphDeploymentId: subgraphDeployment,
                protocolNetwork: "",
                chainId: ""
            })
        );
        vm.mockCall(
            address(ipCollector),
            abi.encodeWithSelector(IIPCollector.accept.selector, signedIAV),
            new bytes(0)
        );
        vm.expectCall(address(ipCollector), abi.encodeCall(IIPCollector.accept, (signedIAV)));
        subgraphService.acceptIAV(allocationID, signedIAV);
    }

    // function _notInUsers(address _candidate) private view returns (bool) {
    //     return
    //         _candidate != users.governor &&
    //         _candidate != users.deployer &&
    //         _candidate != users.indexer &&
    //         _candidate != users.operator &&
    //         _candidate != users.gateway &&
    //         _candidate != users.verifier &&
    //         _candidate != users.delegator &&
    //         _candidate != users.arbitrator &&
    //         _candidate != users.fisherman &&
    //         _candidate != users.rewardsDestination &&
    //         _candidate != users.pauseGuardian;
    // }
}

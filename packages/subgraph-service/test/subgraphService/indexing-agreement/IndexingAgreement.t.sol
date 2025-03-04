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
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SubgraphServiceIndexingAgreementTest is SubgraphServiceTest, Bounder {
    address constant TRANSPARENT_UPGRADEABLE_PROXY_ADMIN = 0xE1C5264f10fad5d1912e5Ba2446a26F5EfdB7482;

    modifier withSafeOperator(address operator) {
        vm.assume(_isSafeServiceProviderAndOperator(operator));
        _;
    }

    /*
     * TESTS
     */

    function test_SubgraphService_Revert_WhenUnsafeAddress_WhenProxyAdmin(
        address serviceProvider,
        address payer,
        bytes16 agreementId
    ) public {
        address operator = TRANSPARENT_UPGRADEABLE_PROXY_ADMIN;
        assertFalse(_isSafeServiceProviderAndOperator(operator));

        vm.expectRevert(TransparentUpgradeableProxy.ProxyDeniedAdminAccess.selector);
        resetPrank(address(operator));
        subgraphService.cancelIAV(serviceProvider, payer, agreementId);
    }

    function test_SubgraphService_Revert_WhenUnsafeAddress_WhenGraphProxyAdmin(uint256 unboundedTokens) public {
        address serviceProvider = 0x15c603B7eaA8eE1a272a69C4af3462F926de777F; // GraphProxyAdmin
        assertFalse(_isSafeServiceProviderAndOperator(serviceProvider));

        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(serviceProvider, tokens);
        resetPrank(serviceProvider);
        vm.expectRevert("Cannot fallback to proxy target");
        staking.provision(serviceProvider, address(subgraphService), tokens, maxSlashingPercentage, disputePeriod);
    }

    function test_SubgraphService_CancelIAV_Revert_WhenPaused(
        address operator,
        address serviceProvider,
        address payer,
        bytes16 agreementId
    ) public withSafeOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        resetPrank(operator);
        subgraphService.cancelIAV(serviceProvider, payer, agreementId);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenPaused(
        address allocationId,
        address operator,
        IIPCollector.SignedIAV calldata signedIAV
    ) public withSafeOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(operator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.acceptIAV(allocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenNotAuthorized(
        address allocationId,
        address operator,
        IIPCollector.SignedIAV calldata signedIAV
    ) public withSafeOperator(operator) {
        vm.assume(operator != signedIAV.iav.serviceProvider);
        resetPrank(operator);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            signedIAV.iav.serviceProvider,
            operator
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIAV(allocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenInvalidProvision(
        address serviceProvider,
        uint256 unboundedTokens,
        address allocationId,
        IIPCollector.SignedIAV memory signedIAV
    ) public withSafeOperator(serviceProvider) {
        uint256 tokens = bound(unboundedTokens, 1, minimumProvisionTokens - 1);
        mint(serviceProvider, tokens);
        resetPrank(serviceProvider);
        _createProvision(serviceProvider, tokens, maxSlashingPercentage, disputePeriod);

        signedIAV.iav.serviceProvider = serviceProvider;
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
        address serviceProvider,
        uint256 unboundedTokens,
        address allocationId,
        IIPCollector.SignedIAV memory signedIAV
    ) public withSafeOperator(serviceProvider) {
        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(serviceProvider, tokens);
        resetPrank(serviceProvider);
        _createProvision(serviceProvider, tokens, maxSlashingPercentage, disputePeriod);
        signedIAV.iav.serviceProvider = serviceProvider;
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            serviceProvider
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
        //     signedIAV.iav.serviceProvider
        // );
        vm.expectRevert("SubgraphService: Data service mismatch");
        vm.prank(params.serviceProvider);
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

    mapping(address => bool) private _serviceProviders;
    mapping(address => bool) private _allocationIds;

    function _setupFuzzyServiceProvider(
        setupFuzzyServiceProviderParams calldata _params
    ) private returns (serviceProviderParams memory) {
        vm.assume(
            _isSafeServiceProviderAndOperator(_params.serviceProvider) && !_serviceProviders[_params.serviceProvider]
        );
        _serviceProviders[_params.serviceProvider] = true;

        (uint256 allocationKey, address allocationId) = boundKeyAndAddr(_params.unboundedAllocationPrivateKey);
        vm.assume(!_allocationIds[allocationId]);
        _allocationIds[allocationId] = true;

        uint256 tokens = bound(_params.unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(_params.serviceProvider, tokens);

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
        setupFuzzyServiceProviderParams calldata _fuzzyParams,
        IIPCollector.SignedIAV memory signedIAV
    ) public {
        serviceProviderParams memory params = _setupFuzzyServiceProvider(_fuzzyParams);
        signedIAV.iav.serviceProvider = params.serviceProvider;
        signedIAV.iav.dataService = address(subgraphService);
        // bytes memory expectedErr = abi.encodeWithSelector(
        //     ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
        //     users.indexer
        // );
        vm.expectRevert("SubgraphService: Invalid IAV metadata");
        vm.prank(params.serviceProvider);
        subgraphService.acceptIAV(params.allocationId, signedIAV);
    }

    // function _sensibleIAVMetadata(serviceProviderParams calldata _params) private returns (bytes memory) {
    //     return
    //         abi.encode(
    //             ISubgraphService.IndexingAgreementVoucherMetadata({
    //                 tokensPerSecond: 0,
    //                 tokensPerEntityPerSecond: 0,
    //                 subgraphDeploymentId: _params.subgraphDeploymentId,
    //                 protocolNetwork: "",
    //                 chainId: ""
    //             })
    //         );
    // }

    function test_SubgraphService_AcceptIAV_Revert_WhenInvalidAllocation(
        setupFuzzyServiceProviderParams calldata _fuzzyParams,
        address invalidAllocationId,
        IIPCollector.SignedIAV memory signedIAV
    ) public {
        serviceProviderParams memory params = _setupFuzzyServiceProvider(_fuzzyParams);
        signedIAV.iav.serviceProvider = params.serviceProvider;
        signedIAV.iav.dataService = address(subgraphService);
        signedIAV.iav.metadata = abi.encode(
            ISubgraphService.IndexingAgreementVoucherMetadata({
                tokensPerSecond: 0,
                tokensPerEntityPerSecond: 0,
                subgraphDeploymentId: params.subgraphDeploymentId,
                protocolNetwork: "",
                chainId: ""
            })
        );
        bytes memory expectedErr = abi.encodeWithSelector(
            Allocation.AllocationDoesNotExist.selector,
            invalidAllocationId
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.serviceProvider);
        subgraphService.acceptIAV(invalidAllocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenServiceProviderMismatchAllocation(
        setupFuzzyServiceProviderParams calldata _fuzzyParamsA,
        setupFuzzyServiceProviderParams calldata _fuzzyParamsB,
        IIPCollector.SignedIAV memory signedIAV
    ) public {
        vm.assume(_fuzzyParamsA.serviceProvider != _fuzzyParamsB.serviceProvider);
        vm.assume(_fuzzyParamsA.unboundedAllocationPrivateKey != _fuzzyParamsB.unboundedAllocationPrivateKey);
        serviceProviderParams memory paramsA = _setupFuzzyServiceProvider(_fuzzyParamsA);
        serviceProviderParams memory paramsB = _setupFuzzyServiceProvider(_fuzzyParamsB);
        signedIAV.iav.serviceProvider = paramsA.serviceProvider;
        signedIAV.iav.dataService = address(subgraphService);
        signedIAV.iav.metadata = abi.encode(
            ISubgraphService.IndexingAgreementVoucherMetadata({
                tokensPerSecond: 0,
                tokensPerEntityPerSecond: 0,
                subgraphDeploymentId: paramsA.subgraphDeploymentId,
                protocolNetwork: "",
                chainId: ""
            })
        );
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceInvalidSomething.selector,
            signedIAV.iav.serviceProvider,
            paramsB.serviceProvider
        );
        vm.expectRevert(expectedErr);
        vm.prank(paramsA.serviceProvider);
        subgraphService.acceptIAV(paramsB.allocationId, signedIAV);
    }

    function test_SubgraphService_AcceptIAV_Revert_WhenDeploymentIdMismatch(
        setupFuzzyServiceProviderParams calldata _fuzzyParams,
        bytes32 wrongSubgraphDeploymentId,
        IIPCollector.SignedIAV memory signedIAV
    ) public {
        vm.assume(_fuzzyParams.subgraphDeploymentId != wrongSubgraphDeploymentId);
        serviceProviderParams memory params = _setupFuzzyServiceProvider(_fuzzyParams);
        signedIAV.iav.serviceProvider = params.serviceProvider;
        signedIAV.iav.dataService = address(subgraphService);
        signedIAV.iav.metadata = abi.encode(
            ISubgraphService.IndexingAgreementVoucherMetadata({
                tokensPerSecond: 0,
                tokensPerEntityPerSecond: 0,
                subgraphDeploymentId: wrongSubgraphDeploymentId,
                protocolNetwork: "",
                chainId: ""
            })
        );
        vm.expectRevert("SubgraphService: SubgraphDeploymentId mismatch");
        vm.prank(params.serviceProvider);
        subgraphService.acceptIAV(params.allocationId, signedIAV);
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

    function _isSafeServiceProviderAndOperator(address _candidate) private view returns (bool) {
        return
            _candidate != address(0) &&
            _candidate != address(TRANSPARENT_UPGRADEABLE_PROXY_ADMIN) &&
            _candidate != address(proxyAdmin);
        // return true;
        // return _candidate != address(0) && _candidate != address(proxyAdmin) && _candidate != otherGraphProxyAdmin;
        // _candidate != users.governor &&
        // _candidate != users.deployer &&
        // _candidate != users.indexer &&
        // _candidate != users.operator &&
        // _candidate != users.gateway &&
        // _candidate != users.verifier &&
        // _candidate != users.delegator &&
        // _candidate != users.arbitrator &&
        // _candidate != users.fisherman &&
        // _candidate != users.rewardsDestination &&
        // _candidate != users.pauseGuardian;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;
import { IAuthorizable } from "@graphprotocol/horizon/contracts/interfaces/IAuthorizable.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { IPaymentsCollector } from "@graphprotocol/horizon/contracts/interfaces/IPaymentsCollector.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { Bounder } from "@graphprotocol/horizon/test/utils/Bounder.t.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceIndexingAgreementSharedTest is SubgraphServiceTest, Bounder {
    struct SetupTestIndexerParams {
        address indexer;
        string indexerLabel;
        uint256 unboundedTokens;
        uint256 unboundedAllocationPrivateKey;
        bytes32 subgraphDeploymentId;
    }

    struct TestIndexerParams {
        address indexer;
        address allocationId;
        bytes32 subgraphDeploymentId;
        uint256 tokens;
    }

    address internal constant TRANSPARENT_UPGRADEABLE_PROXY_ADMIN = 0xE1C5264f10fad5d1912e5Ba2446a26F5EfdB7482;

    mapping(address indexer => bool registered) internal _registeredIndexers;

    mapping(address allocationId => bool used) internal _allocationIds;

    modifier withSafeIndexerOrOperator(address operator) {
        vm.assume(_isSafeSubgraphServiceCaller(operator));
        _;
    }

    /*
     * HELPERS
     */

    function _resetPrank(address _addr) internal returns (address) {
        address originalPrankAddress = msg.sender;
        resetPrank(_addr);

        return originalPrankAddress;
    }

    function _stopOrResetPrank(address _originalSender) internal {
        if (_originalSender == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
            vm.stopPrank();
        } else {
            resetPrank(_originalSender);
        }
    }

    function _acceptAgreement(
        TestIndexerParams memory _params,
        IRecurringCollector.SignedRCA memory _signedRCA
    ) internal returns (IRecurringCollector.SignedRCA memory) {
        vm.assume(_signedRCA.rca.agreementId != bytes16(0));
        ISubgraphService.AcceptIndexingAgreementMetadata memory metadata = _createRCAMetadataV1(
            _params.subgraphDeploymentId
        );
        _signedRCA.rca.serviceProvider = _params.indexer;
        _signedRCA.rca.dataService = address(subgraphService);
        _signedRCA.rca.metadata = abi.encode(metadata);

        _mockCollectorAccept(address(recurringCollector), _signedRCA);

        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.IndexingAgreementAccepted(
            _signedRCA.rca.serviceProvider,
            _signedRCA.rca.payer,
            _signedRCA.rca.agreementId,
            _params.allocationId,
            metadata.subgraphDeploymentId,
            metadata.version,
            metadata.terms
        );

        resetPrank(_params.indexer);
        subgraphService.acceptIndexingAgreement(_params.allocationId, _signedRCA);
        return _signedRCA;
    }

    function _cancelAgreementBy(address _indexer, address _payer, bytes16 _agreementId, bool _byIndexer) internal {
        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.IndexingAgreementCanceled(_indexer, _payer, _agreementId, _byIndexer ? _indexer : _payer);
        _byIndexer ? _cancelAgreementByIndexer(_indexer, _agreementId) : _cancelAgreementByPayer(_payer, _agreementId);
    }

    function _cancelAgreementByPayer(address _payer, bytes16 _agreementId) internal {
        _mockCollectorIsAuthorized(address(recurringCollector), _payer, _payer, true);

        _mockCollectorCancel(address(recurringCollector), _agreementId);
        vm.assume(_isSafeSubgraphServiceCaller(_payer));
        resetPrank(_payer);
        subgraphService.cancelIndexingAgreementByPayer(_agreementId);
    }

    function _cancelAgreementByIndexer(address _indexer, bytes16 _agreementId) internal {
        _mockCollectorCancel(address(recurringCollector), _agreementId);
        resetPrank(_indexer);
        subgraphService.cancelIndexingAgreement(_indexer, _agreementId);
    }

    function _setupTestIndexer(SetupTestIndexerParams calldata _params) internal returns (TestIndexerParams memory) {
        vm.label(_params.indexer, string.concat("indexer-", _params.indexerLabel));
        vm.assume(_isSafeSubgraphServiceCaller(_params.indexer) && !_registeredIndexers[_params.indexer]);
        _registeredIndexers[_params.indexer] = true;

        (uint256 allocationKey, address allocationId) = boundKeyAndAddr(_params.unboundedAllocationPrivateKey);
        vm.assume(!_allocationIds[allocationId]);
        _allocationIds[allocationId] = true;

        uint256 tokens = bound(_params.unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(_params.indexer, tokens);

        address originalPrank = _resetPrank(_params.indexer);
        _createProvision(_params.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(_params.indexer, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            _params.indexer,
            _params.subgraphDeploymentId,
            allocationKey,
            tokens
        );
        _startService(_params.indexer, data);
        _stopOrResetPrank(originalPrank);

        return
            TestIndexerParams({
                indexer: _params.indexer,
                allocationId: allocationId,
                subgraphDeploymentId: _params.subgraphDeploymentId,
                tokens: tokens
            });
    }

    function _mockCollectorIsAuthorized(
        address _recurringCollector,
        address _payer,
        address _indexer,
        bool _result
    ) internal {
        vm.mockCall(
            _recurringCollector,
            abi.encodeWithSelector(IAuthorizable.isAuthorized.selector, _payer, _indexer),
            abi.encode(_result)
        );
        vm.expectCall(_recurringCollector, abi.encodeCall(IAuthorizable.isAuthorized, (_payer, _indexer)));
    }

    function _mockCollectorCancel(address _recurringCollector, bytes16 _agreementId) internal {
        vm.mockCall(
            _recurringCollector,
            abi.encodeWithSelector(IRecurringCollector.cancel.selector, _agreementId),
            new bytes(0)
        );
        vm.expectCall(_recurringCollector, abi.encodeCall(IRecurringCollector.cancel, (_agreementId)));
    }

    function _mockCollectorAccept(
        address _recurringCollector,
        IRecurringCollector.SignedRCA memory _signedRCA
    ) internal {
        vm.mockCall(
            _recurringCollector,
            abi.encodeWithSelector(IRecurringCollector.accept.selector, _signedRCA),
            new bytes(0)
        );
        vm.expectCall(_recurringCollector, abi.encodeCall(IRecurringCollector.accept, (_signedRCA)));
    }

    function _mockCollectorUpgrade(
        address _recurringCollector,
        IRecurringCollector.SignedRCAU memory _signedRCAU
    ) internal {
        vm.mockCall(
            _recurringCollector,
            abi.encodeWithSelector(IRecurringCollector.upgrade.selector, _signedRCAU),
            new bytes(0)
        );
        vm.expectCall(_recurringCollector, abi.encodeCall(IRecurringCollector.upgrade, (_signedRCAU)));
    }

    function _mockCollectorCollect(address _recurringCollector, bytes memory _data, uint256 _tokensCollected) internal {
        vm.mockCall(
            _recurringCollector,
            abi.encodeWithSelector(IPaymentsCollector.collect.selector, IGraphPayments.PaymentTypes.IndexingFee, _data),
            abi.encode(_tokensCollected)
        );
        vm.expectCall(
            _recurringCollector,
            abi.encodeCall(IPaymentsCollector.collect, (IGraphPayments.PaymentTypes.IndexingFee, _data))
        );
    }

    function _isSafeSubgraphServiceCaller(address _candidate) internal view returns (bool) {
        return
            _candidate != address(0) &&
            _candidate != address(TRANSPARENT_UPGRADEABLE_PROXY_ADMIN) &&
            _candidate != address(proxyAdmin);
    }

    function _createRCAMetadataV1(
        bytes32 _subgraphDeploymentId
    ) internal pure returns (ISubgraphService.AcceptIndexingAgreementMetadata memory) {
        return
            ISubgraphService.AcceptIndexingAgreementMetadata({
                subgraphDeploymentId: _subgraphDeploymentId,
                version: ISubgraphService.IndexingAgreementVersion.V1,
                terms: abi.encode(
                    ISubgraphService.IndexingAgreementTermsV1({ tokensPerSecond: 0, tokensPerEntityPerSecond: 0 })
                )
            });
    }

    function _createRCAUMetadataV1(
        uint256 _tokensPerSecond,
        uint256 _tokensPerEntityPerSecond
    ) internal pure returns (ISubgraphService.UpgradeIndexingAgreementMetadata memory) {
        return
            ISubgraphService.UpgradeIndexingAgreementMetadata({
                version: ISubgraphService.IndexingAgreementVersion.V1,
                terms: abi.encode(
                    ISubgraphService.IndexingAgreementTermsV1({
                        tokensPerSecond: _tokensPerSecond,
                        tokensPerEntityPerSecond: _tokensPerEntityPerSecond
                    })
                )
            });
    }

    function _encodeCollectDataV1(
        bytes16 _agreementId,
        uint256 _entities,
        bytes32 _poi,
        uint256 _epoch
    ) internal pure returns (bytes memory) {
        return abi.encode(_agreementId, abi.encode(_entities, _poi, _epoch));
    }

    function _encodeRCAMetadataV1(
        bytes32 _subgraphDeploymentId,
        ISubgraphService.IndexingAgreementTermsV1 memory _params
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                ISubgraphService.AcceptIndexingAgreementMetadata({
                    subgraphDeploymentId: _subgraphDeploymentId,
                    version: ISubgraphService.IndexingAgreementVersion.V1,
                    terms: abi.encode(_params)
                })
            );
    }

    function _encodeRCAUMetadataV1(
        ISubgraphService.UpgradeIndexingAgreementMetadata memory _t
    ) internal pure returns (bytes memory) {
        return abi.encode(_t);
    }
}

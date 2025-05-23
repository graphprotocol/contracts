// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";

import { Bounder } from "@graphprotocol/horizon/test/unit/utils/Bounder.t.sol";
import { RecurringCollectorHelper } from "@graphprotocol/horizon/test/unit/payments/recurring-collector/RecurringCollectorHelper.t.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceIndexingAgreementSharedTest is SubgraphServiceTest, Bounder {
    struct Context {
        PayerState payer;
        IndexerState[] indexers;
        mapping(address allocationId => address indexer) allocations;
        ContextInternal ctxInternal;
    }

    struct IndexerState {
        address addr;
        address allocationId;
        bytes32 subgraphDeploymentId;
        uint256 tokens;
    }

    struct PayerState {
        address signer;
        uint256 signerPrivateKey;
    }

    struct ContextInternal {
        IndexerSeed[] indexers;
        Seed seed;
        bool initialized;
    }

    struct Seed {
        IndexerSeed indexer0;
        IndexerSeed indexer1;
        IRecurringCollector.RecurringCollectionAgreement rca;
        IRecurringCollector.RecurringCollectionAgreementUpdate rcau;
        IndexingAgreement.IndexingAgreementTermsV1 termsV1;
        PayerSeed payer;
    }

    struct IndexerSeed {
        address addr;
        string label;
        uint256 unboundedProvisionTokens;
        uint256 unboundedAllocationPrivateKey;
        bytes32 subgraphDeploymentId;
    }

    struct PayerSeed {
        uint256 unboundedSignerPrivateKey;
    }

    Context internal _context;

    bytes32 internal constant TRANSPARENT_UPGRADEABLE_PROXY_ADMIN_ADDRESS_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address internal constant GRAPH_PROXY_ADMIN_ADDRESS = 0x15c603B7eaA8eE1a272a69C4af3462F926de777F;

    RecurringCollectorHelper internal _recurringCollectorHelper;

    modifier withSafeIndexerOrOperator(address operator) {
        vm.assume(_isSafeSubgraphServiceCaller(operator));
        _;
    }

    function setUp() public override {
        super.setUp();

        _recurringCollectorHelper = new RecurringCollectorHelper(recurringCollector);
    }

    /*
     * HELPERS
     */

    function _subgraphServiceSafePrank(address _addr) internal returns (address) {
        address originalPrankAddress = msg.sender;
        vm.assume(_isSafeSubgraphServiceCaller(_addr));
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

    function _cancelAgreement(
        Context storage _ctx,
        bytes16 _agreementId,
        address _indexer,
        address _payer,
        IRecurringCollector.CancelAgreementBy _by
    ) internal {
        bool byIndexer = _by == IRecurringCollector.CancelAgreementBy.ServiceProvider;
        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementCanceled(_indexer, _payer, _agreementId, byIndexer ? _indexer : _payer);

        if (byIndexer) {
            _subgraphServiceSafePrank(_indexer);
            subgraphService.cancelIndexingAgreement(_indexer, _agreementId);
        } else {
            _subgraphServiceSafePrank(_ctx.payer.signer);
            subgraphService.cancelIndexingAgreementByPayer(_agreementId);
        }
    }

    function _withIndexer(Context storage _ctx) internal returns (IndexerState memory) {
        require(_ctx.ctxInternal.indexers.length > 0, "No indexer seeds available");

        IndexerSeed memory indexerSeed = _ctx.ctxInternal.indexers[_ctx.ctxInternal.indexers.length - 1];
        _ctx.ctxInternal.indexers.pop();

        indexerSeed.label = string.concat("_withIndexer-", Strings.toString(_ctx.ctxInternal.indexers.length));

        return _setupIndexer(_ctx, indexerSeed);
    }

    function _setupIndexer(Context storage _ctx, IndexerSeed memory _seed) internal returns (IndexerState memory) {
        vm.assume(_getIndexer(_ctx, _seed.addr).addr == address(0));

        (uint256 allocationKey, address allocationId) = boundKeyAndAddr(_seed.unboundedAllocationPrivateKey);
        vm.assume(_ctx.allocations[allocationId] == address(0));
        _ctx.allocations[allocationId] = _seed.addr;

        uint256 tokens = bound(_seed.unboundedProvisionTokens, minimumProvisionTokens, MAX_TOKENS);

        IndexerState memory indexer = IndexerState({
            addr: _seed.addr,
            allocationId: allocationId,
            subgraphDeploymentId: _seed.subgraphDeploymentId,
            tokens: tokens
        });
        vm.label(indexer.addr, string.concat("_setupIndexer-", _seed.label));

        // Mint tokens to the indexer
        mint(_seed.addr, tokens);

        // Create the indexer
        address originalPrank = _subgraphServiceSafePrank(indexer.addr);
        _createProvision(indexer.addr, indexer.tokens, fishermanRewardPercentage, disputePeriod);
        _register(indexer.addr, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            indexer.addr,
            indexer.subgraphDeploymentId,
            allocationKey,
            indexer.tokens
        );
        _startService(indexer.addr, data);

        _ctx.indexers.push(indexer);

        _stopOrResetPrank(originalPrank);

        return indexer;
    }

    function _withAcceptedIndexingAgreement(
        Context storage _ctx,
        IndexerState memory _indexerState
    ) internal returns (IRecurringCollector.SignedRCA memory) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _ctx.ctxInternal.seed.rca;

        IndexingAgreement.AcceptIndexingAgreementMetadata memory metadata = _newAcceptIndexingAgreementMetadataV1(
            _indexerState.subgraphDeploymentId
        );
        rca.serviceProvider = _indexerState.addr;
        rca.dataService = address(subgraphService);
        rca.metadata = abi.encode(metadata);

        rca = _recurringCollectorHelper.sensibleRCA(rca);

        IRecurringCollector.SignedRCA memory signedRCA = _recurringCollectorHelper.generateSignedRCA(
            rca,
            _ctx.payer.signerPrivateKey
        );
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, _ctx.payer.signerPrivateKey);

        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementAccepted(
            rca.serviceProvider,
            rca.payer,
            rca.agreementId,
            _indexerState.allocationId,
            metadata.subgraphDeploymentId,
            metadata.version,
            metadata.terms
        );
        _subgraphServiceSafePrank(_indexerState.addr);
        subgraphService.acceptIndexingAgreement(_indexerState.allocationId, signedRCA);

        return signedRCA;
    }

    function _newCtx(Seed memory _seed) internal returns (Context storage) {
        require(_context.ctxInternal.initialized == false, "Context already initialized");
        Context storage ctx = _context;

        // Initialize
        ctx.ctxInternal.initialized = true;

        // Setup seeds
        ctx.ctxInternal.seed = _seed;
        ctx.ctxInternal.indexers.push(_seed.indexer0);
        ctx.ctxInternal.indexers.push(_seed.indexer1);

        // Setup payer
        ctx.payer.signerPrivateKey = boundKey(ctx.ctxInternal.seed.payer.unboundedSignerPrivateKey);
        ctx.payer.signer = vm.addr(ctx.payer.signerPrivateKey);

        return ctx;
    }

    function _generateAcceptableSignedRCA(
        Context storage _ctx,
        address _indexerAddress
    ) internal returns (IRecurringCollector.SignedRCA memory) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _generateAcceptableRecurringCollectionAgreement(
            _ctx,
            _indexerAddress
        );
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, _ctx.payer.signerPrivateKey);

        return _recurringCollectorHelper.generateSignedRCA(rca, _ctx.payer.signerPrivateKey);
    }

    function _generateAcceptableRecurringCollectionAgreement(
        Context storage _ctx,
        address _indexerAddress
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        IndexerState memory indexer = _requireIndexer(_ctx, _indexerAddress);
        IndexingAgreement.AcceptIndexingAgreementMetadata memory metadata = _newAcceptIndexingAgreementMetadataV1(
            indexer.subgraphDeploymentId
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca = _ctx.ctxInternal.seed.rca;
        rca.serviceProvider = indexer.addr;
        rca.dataService = address(subgraphService);
        rca.metadata = abi.encode(metadata);

        return _recurringCollectorHelper.sensibleRCA(rca);
    }

    function _generateAcceptableSignedRCAU(
        Context storage _ctx,
        IRecurringCollector.RecurringCollectionAgreement memory _rca
    ) internal view returns (IRecurringCollector.SignedRCAU memory) {
        return
            _recurringCollectorHelper.generateSignedRCAU(
                _generateAcceptableRecurringCollectionAgreementUpdate(_ctx, _rca),
                _ctx.payer.signerPrivateKey
            );
    }

    function _generateAcceptableRecurringCollectionAgreementUpdate(
        Context storage _ctx,
        IRecurringCollector.RecurringCollectionAgreement memory _rca
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _ctx.ctxInternal.seed.rcau;
        rcau.agreementId = _rca.agreementId;
        rcau.metadata = _encodeUpdateIndexingAgreementMetadataV1(
            _newUpdateIndexingAgreementMetadataV1(
                _ctx.ctxInternal.seed.termsV1.tokensPerSecond,
                _ctx.ctxInternal.seed.termsV1.tokensPerEntityPerSecond
            )
        );
        return _recurringCollectorHelper.sensibleRCAU(rcau);
    }

    function _requireIndexer(Context storage _ctx, address _indexer) internal view returns (IndexerState memory) {
        IndexerState memory indexerState = _getIndexer(_ctx, _indexer);
        require(indexerState.addr != address(0), "Indexer not found in context");

        return indexerState;
    }

    function _getIndexer(Context storage _ctx, address _indexer) internal view returns (IndexerState memory zero) {
        for (uint256 i = 0; i < _ctx.indexers.length; i++) {
            if (_ctx.indexers[i].addr == _indexer) {
                return _ctx.indexers[i];
            }
        }

        return zero;
    }

    function _isSafeSubgraphServiceCaller(address _candidate) internal view returns (bool) {
        return
            _candidate != address(0) &&
            _candidate != address(_transparentUpgradeableProxyAdmin()) &&
            _candidate != address(proxyAdmin);
    }

    function _transparentUpgradeableProxyAdmin() internal view returns (address) {
        return
            address(
                uint160(uint256(vm.load(address(subgraphService), TRANSPARENT_UPGRADEABLE_PROXY_ADMIN_ADDRESS_SLOT)))
            );
    }

    function _newAcceptIndexingAgreementMetadataV1(
        bytes32 _subgraphDeploymentId
    ) internal pure returns (IndexingAgreement.AcceptIndexingAgreementMetadata memory) {
        return
            IndexingAgreement.AcceptIndexingAgreementMetadata({
                subgraphDeploymentId: _subgraphDeploymentId,
                version: IndexingAgreement.IndexingAgreementVersion.V1,
                terms: abi.encode(
                    IndexingAgreement.IndexingAgreementTermsV1({ tokensPerSecond: 0, tokensPerEntityPerSecond: 0 })
                )
            });
    }

    function _newUpdateIndexingAgreementMetadataV1(
        uint256 _tokensPerSecond,
        uint256 _tokensPerEntityPerSecond
    ) internal pure returns (IndexingAgreement.UpdateIndexingAgreementMetadata memory) {
        return
            IndexingAgreement.UpdateIndexingAgreementMetadata({
                version: IndexingAgreement.IndexingAgreementVersion.V1,
                terms: abi.encode(
                    IndexingAgreement.IndexingAgreementTermsV1({
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
        uint256 _poiBlock,
        bytes memory _metadata
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                _agreementId,
                abi.encode(
                    IndexingAgreement.CollectIndexingFeeDataV1({
                        entities: _entities,
                        poi: _poi,
                        poiBlockNumber: _poiBlock,
                        metadata: _metadata
                    })
                )
            );
    }

    function _encodeAcceptIndexingAgreementMetadataV1(
        bytes32 _subgraphDeploymentId,
        IndexingAgreement.IndexingAgreementTermsV1 memory _terms
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                IndexingAgreement.AcceptIndexingAgreementMetadata({
                    subgraphDeploymentId: _subgraphDeploymentId,
                    version: IndexingAgreement.IndexingAgreementVersion.V1,
                    terms: abi.encode(_terms)
                })
            );
    }

    function _encodeUpdateIndexingAgreementMetadataV1(
        IndexingAgreement.UpdateIndexingAgreementMetadata memory _t
    ) internal pure returns (bytes memory) {
        return abi.encode(_t);
    }
}

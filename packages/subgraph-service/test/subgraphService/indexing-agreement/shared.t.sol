// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;
import { IAuthorizable } from "@graphprotocol/horizon/contracts/interfaces/IAuthorizable.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { IPaymentsCollector } from "@graphprotocol/horizon/contracts/interfaces/IPaymentsCollector.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { Bounder } from "@graphprotocol/horizon/test/utils/Bounder.t.sol";
import { RecurringCollectorHelper } from "@graphprotocol/horizon/test/payments/recurring-collector/RecurringCollectorHelper.t.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceIndexingAgreementSharedTest is SubgraphServiceTest, Bounder {
    struct Context {
        PayerState payer;
        IndexerState[] indexers;
        mapping(address allocationId => address indexer) allocations;
        ContextInternal _internal;
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
        IRecurringCollector.RecurringCollectionAgreementUpgrade rcau;
        ISubgraphService.IndexingAgreementTermsV1 termsV1;
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

    address internal constant TRANSPARENT_UPGRADEABLE_PROXY_ADMIN = 0xE1C5264f10fad5d1912e5Ba2446a26F5EfdB7482;

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
        Context storage ctx,
        bytes16 _agreementId,
        address _indexer,
        address _payer,
        IRecurringCollector.CancelAgreementBy _by
    ) internal {
        bool byIndexer = _by == IRecurringCollector.CancelAgreementBy.ServiceProvider;
        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.IndexingAgreementCanceled(_indexer, _payer, _agreementId, byIndexer ? _indexer : _payer);

        if (byIndexer) {
            _subgraphServiceSafePrank(_indexer);
            subgraphService.cancelIndexingAgreement(_indexer, _agreementId);
        } else {
            _subgraphServiceSafePrank(ctx.payer.signer);
            subgraphService.cancelIndexingAgreementByPayer(_agreementId);
        }
    }

    function _isSafeSubgraphServiceCaller(address _candidate) internal view returns (bool) {
        return
            _candidate != address(0) &&
            _candidate != address(TRANSPARENT_UPGRADEABLE_PROXY_ADMIN) &&
            _candidate != address(proxyAdmin);
    }

    function _newAcceptIndexingAgreementMetadataV1(
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

    function _newUpgradeIndexingAgreementMetadataV1(
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

    function _encodeAcceptIndexingAgreementMetadataV1(
        bytes32 _subgraphDeploymentId,
        ISubgraphService.IndexingAgreementTermsV1 memory _terms
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                ISubgraphService.AcceptIndexingAgreementMetadata({
                    subgraphDeploymentId: _subgraphDeploymentId,
                    version: ISubgraphService.IndexingAgreementVersion.V1,
                    terms: abi.encode(_terms)
                })
            );
    }

    function _encodeUpgradeIndexingAgreementMetadataV1(
        ISubgraphService.UpgradeIndexingAgreementMetadata memory _t
    ) internal pure returns (bytes memory) {
        return abi.encode(_t);
    }

    function _withIndexer(Context storage ctx) internal returns (IndexerState memory) {
        require(ctx._internal.indexers.length > 0, "No indexer seeds available");

        IndexerSeed memory indexerSeed = ctx._internal.indexers[ctx._internal.indexers.length - 1];
        ctx._internal.indexers.pop();

        indexerSeed.label = string.concat("_withIndexer-", Strings.toString(ctx._internal.indexers.length));

        return _setupIndexer(ctx, indexerSeed);
    }

    function _setupIndexer(Context storage ctx, IndexerSeed memory _seed) internal returns (IndexerState memory) {
        vm.assume(_getIndexer(ctx, _seed.addr).addr == address(0));

        (uint256 allocationKey, address allocationId) = boundKeyAndAddr(_seed.unboundedAllocationPrivateKey);
        vm.assume(ctx.allocations[allocationId] == address(0));
        ctx.allocations[allocationId] = _seed.addr;

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
        _createProvision(indexer.addr, indexer.tokens, maxSlashingPercentage, disputePeriod);
        _register(indexer.addr, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            indexer.addr,
            indexer.subgraphDeploymentId,
            allocationKey,
            indexer.tokens
        );
        _startService(indexer.addr, data);

        ctx.indexers.push(indexer);

        _stopOrResetPrank(originalPrank);

        return indexer;
    }

    function _withAcceptedIndexingAgreement(
        Context storage _ctx,
        IndexerState memory _indexerState
    ) internal returns (IRecurringCollector.SignedRCA memory) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _ctx._internal.seed.rca;

        ISubgraphService.AcceptIndexingAgreementMetadata memory metadata = _newAcceptIndexingAgreementMetadataV1(
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
        emit ISubgraphService.IndexingAgreementAccepted(
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

    function _generateAcceptableRecurringCollectionAgreement(
        Context storage ctx,
        address indexerAddress
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        IndexerState memory indexer = _requireIndexer(ctx, indexerAddress);
        ISubgraphService.AcceptIndexingAgreementMetadata memory metadata = _newAcceptIndexingAgreementMetadataV1(
            indexer.subgraphDeploymentId
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca = ctx._internal.seed.rca;
        rca.serviceProvider = indexer.addr;
        rca.dataService = address(subgraphService);
        rca.metadata = abi.encode(metadata);

        return _recurringCollectorHelper.sensibleRCA(rca);
    }

    function _generateAcceptableSignedRCA(
        Context storage ctx,
        address indexerAddress
    ) internal returns (IRecurringCollector.SignedRCA memory) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _generateAcceptableRecurringCollectionAgreement(
            ctx,
            indexerAddress
        );
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, ctx.payer.signerPrivateKey);

        return _recurringCollectorHelper.generateSignedRCA(rca, ctx.payer.signerPrivateKey);
    }

    function _generateAcceptableSignedRCAU(
        Context storage ctx,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal view returns (IRecurringCollector.SignedRCAU memory) {
        return
            _recurringCollectorHelper.generateSignedRCAU(
                _generateAcceptableRecurringCollectionAgreementUpgrade(ctx, rca),
                ctx.payer.signerPrivateKey
            );
    }

    function _generateAcceptableRecurringCollectionAgreementUpgrade(
        Context storage ctx,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreementUpgrade memory) {
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = ctx._internal.seed.rcau;
        rcau.agreementId = rca.agreementId;
        rcau.metadata = _encodeUpgradeIndexingAgreementMetadataV1(
            _newUpgradeIndexingAgreementMetadataV1(
                ctx._internal.seed.termsV1.tokensPerSecond,
                ctx._internal.seed.termsV1.tokensPerEntityPerSecond
            )
        );
        return _recurringCollectorHelper.sensibleRCAU(rcau);
    }

    function _requireIndexer(Context storage ctx, address indexer) internal view returns (IndexerState memory) {
        IndexerState memory indexerState = _getIndexer(ctx, indexer);
        require(indexerState.addr != address(0), "Indexer not found in context");

        return indexerState;
    }

    function _getIndexer(Context storage ctx, address indexer) internal view returns (IndexerState memory zero) {
        for (uint256 i = 0; i < ctx.indexers.length; i++) {
            if (ctx.indexers[i].addr == indexer) {
                return ctx.indexers[i];
            }
        }

        return zero;
    }

    function _newCtx(Seed memory _seed) internal returns (Context storage) {
        require(_context._internal.initialized == false, "Context already initialized");
        Context storage ctx = _context;

        // Initialize
        ctx._internal.initialized = true;

        // Setup seeds
        ctx._internal.seed = _seed;
        ctx._internal.indexers.push(_seed.indexer0);
        ctx._internal.indexers.push(_seed.indexer1);

        // Setup payer
        ctx.payer.signerPrivateKey = boundKey(ctx._internal.seed.payer.unboundedSignerPrivateKey);
        ctx.payer.signer = vm.addr(ctx.payer.signerPrivateKey);

        return ctx;
    }
}

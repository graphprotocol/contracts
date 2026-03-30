// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
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
        bool initialized;
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
        bool placeholder;
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

        _recurringCollectorHelper = new RecurringCollectorHelper(recurringCollector, recurringCollectorProxyAdmin);
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
        bool byIndexer
    ) internal {
        bytes32 termsHash = recurringCollector.getAgreementVersionAt(_agreementId, 0).versionHash;
        if (byIndexer) {
            _subgraphServiceSafePrank(_indexer);
            recurringCollector.cancel(_agreementId, termsHash, 0);
        } else {
            _subgraphServiceSafePrank(_payer);
            recurringCollector.cancel(_agreementId, termsHash, 0);
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
        // Exclude named test users: mint() uses deal() which SETS (not adds) token balances,
        // so a collision would overwrite the user's initial balance, then staking drains it to 0.
        vm.assume(!_isTestUser(_seed.addr));

        (uint256 allocationKey, address allocationId) = boundKeyAndAddr(_seed.unboundedAllocationPrivateKey);
        vm.assume(_ctx.allocations[allocationId] == address(0));
        _ctx.allocations[allocationId] = _seed.addr;

        uint256 tokens = bound(_seed.unboundedProvisionTokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);

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
        _createProvision(indexer.addr, indexer.tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
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
    ) internal returns (IRecurringCollector.RecurringCollectionAgreement memory, bytes16 agreementId) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _ctx.ctxInternal.seed.rca;

        IndexingAgreement.AcceptIndexingAgreementMetadata memory metadata = _newAcceptIndexingAgreementMetadataV1(
            _indexerState.subgraphDeploymentId
        );
        rca.serviceProvider = _indexerState.addr;
        rca.dataService = address(subgraphService);
        rca.metadata = abi.encode(metadata);

        rca = _recurringCollectorHelper.sensibleRCA(rca);

        // Generate deterministic agreement ID for event expectation
        agreementId = recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        // Step 1: Payer submits offer to the collector
        vm.prank(rca.payer);
        bytes16 offeredId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        assertEq(offeredId, agreementId);

        // Step 2: Service provider accepts via RC, which callbacks to SS
        bytes32 versionHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementAccepted(
            rca.serviceProvider,
            rca.payer,
            agreementId,
            _indexerState.allocationId,
            metadata.subgraphDeploymentId,
            metadata.version,
            metadata.terms
        );
        vm.prank(_indexerState.addr);
        recurringCollector.accept(agreementId, versionHash, abi.encode(_indexerState.allocationId), 0);

        return (rca, agreementId);
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

        ctx.payer.initialized = true;

        return ctx;
    }

    function _generateAcceptableRCA(
        Context storage _ctx,
        address _indexerAddress
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return _generateAcceptableRecurringCollectionAgreement(_ctx, _indexerAddress);
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

    function _generateAcceptableRCAU(
        Context storage _ctx,
        IRecurringCollector.RecurringCollectionAgreement memory _rca
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        IRecurringCollector.RecurringCollectionAgreementUpdate
            memory rcau = _generateAcceptableRecurringCollectionAgreementUpdate(_ctx, _rca);
        // Set correct nonce for first update (should be 1)
        rcau.nonce = 1;
        return rcau;
    }

    function _generateAcceptableRecurringCollectionAgreementUpdate(
        Context storage _ctx,
        IRecurringCollector.RecurringCollectionAgreement memory _rca
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _ctx.ctxInternal.seed.rcau;
        // Generate deterministic agreement ID for the update
        rcau.agreementId = recurringCollector.generateAgreementId(
            _rca.payer,
            _rca.dataService,
            _rca.serviceProvider,
            _rca.deadline,
            _rca.nonce
        );
        // Apply sensible bounds to RCAU fields first, so maxOngoingTokensPerSecond is known
        rcau = _recurringCollectorHelper.sensibleRCAU(rcau, _rca.payer);
        // Bound metadata terms against the RCAU's maxOngoingTokensPerSecond (not the RCA's)
        // since the contract validates against the update's maxOngoingTokensPerSecond
        rcau.metadata = _encodeUpdateIndexingAgreementMetadataV1(
            _newUpdateIndexingAgreementMetadataV1(
                bound(_ctx.ctxInternal.seed.termsV1.tokensPerSecond, 0, rcau.maxOngoingTokensPerSecond),
                _ctx.ctxInternal.seed.termsV1.tokensPerEntityPerSecond
            )
        );
        return rcau;
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

    function _isTestUser(address _addr) internal view returns (bool) {
        return
            _addr == users.governor ||
            _addr == users.deployer ||
            _addr == users.indexer ||
            _addr == users.operator ||
            _addr == users.gateway ||
            _addr == users.verifier ||
            _addr == users.delegator ||
            _addr == users.arbitrator ||
            _addr == users.fisherman ||
            _addr == users.rewardsDestination ||
            _addr == users.pauseGuardian;
    }

    function _isProtocolContract(address _addr) internal view returns (bool) {
        return
            _addr == address(escrow) ||
            _addr == address(graphPayments) ||
            _addr == address(staking) ||
            _addr == address(subgraphService) ||
            _addr == address(recurringCollector) ||
            _addr == address(token);
    }

    function _isSafeSubgraphServiceCaller(address _candidate) internal view returns (bool) {
        return
            _candidate != address(0) &&
            _candidate != address(_transparentUpgradeableProxyAdmin()) &&
            _candidate != address(proxyAdmin) &&
            !_isProtocolContract(_candidate);
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
            _newAcceptIndexingAgreementMetadataV1Terms(
                _subgraphDeploymentId,
                abi.encode(
                    IndexingAgreement.IndexingAgreementTermsV1({ tokensPerSecond: 0, tokensPerEntityPerSecond: 0 })
                )
            );
    }

    function _newAcceptIndexingAgreementMetadataV1Terms(
        bytes32 _subgraphDeploymentId,
        bytes memory _terms
    ) internal pure returns (IndexingAgreement.AcceptIndexingAgreementMetadata memory) {
        return
            IndexingAgreement.AcceptIndexingAgreementMetadata({
                subgraphDeploymentId: _subgraphDeploymentId,
                version: IIndexingAgreement.IndexingAgreementVersion.V1,
                terms: _terms
            });
    }

    function _newUpdateIndexingAgreementMetadataV1(
        uint256 _tokensPerSecond,
        uint256 _tokensPerEntityPerSecond
    ) internal pure returns (IndexingAgreement.UpdateIndexingAgreementMetadata memory) {
        return
            IndexingAgreement.UpdateIndexingAgreementMetadata({
                version: IIndexingAgreement.IndexingAgreementVersion.V1,
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
        return _encodeCollectData(_agreementId, _encodeV1Data(_entities, _poi, _poiBlock, _metadata));
    }

    function _encodeCollectData(bytes16 _agreementId, bytes memory _nestedData) internal pure returns (bytes memory) {
        return abi.encode(_agreementId, _nestedData);
    }

    function _encodeV1Data(
        uint256 _entities,
        bytes32 _poi,
        uint256 _poiBlock,
        bytes memory _metadata
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                IndexingAgreement.CollectIndexingFeeDataV1({
                    entities: _entities,
                    poi: _poi,
                    poiBlockNumber: _poiBlock,
                    metadata: _metadata,
                    maxSlippage: type(uint256).max
                })
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
                    version: IIndexingAgreement.IndexingAgreementVersion.V1,
                    terms: abi.encode(_terms)
                })
            );
    }

    function _encodeUpdateIndexingAgreementMetadataV1(
        IndexingAgreement.UpdateIndexingAgreementMetadata memory _t
    ) internal pure returns (bytes memory) {
        return abi.encode(_t);
    }

    function _assertEqualAgreement(
        IRecurringCollector.RecurringCollectionAgreement memory _expected,
        IIndexingAgreement.AgreementWrapper memory _actual
    ) internal pure {
        assertEq(_expected.dataService, _actual.collectorAgreement.dataService);
        assertEq(_expected.payer, _actual.collectorAgreement.payer);
        assertEq(_expected.serviceProvider, _actual.collectorAgreement.serviceProvider);
    }
}

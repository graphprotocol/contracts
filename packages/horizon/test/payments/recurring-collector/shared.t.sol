// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsCollector } from "../../../contracts/interfaces/IPaymentsCollector.sol";
import { IRecurringCollector } from "../../../contracts/interfaces/IRecurringCollector.sol";
import { RecurringCollector } from "../../../contracts/payments/collectors/RecurringCollector.sol";

import { Bounder } from "../../utils/Bounder.t.sol";
import { RecurringCollectorControllerMock } from "./RecurringCollectorControllerMock.t.sol";
import { PaymentsEscrowMock } from "./PaymentsEscrowMock.t.sol";
import { RecurringCollectorHelper } from "./RecurringCollectorHelper.t.sol";

contract RecurringCollectorSharedTest is Test, Bounder {
    struct FuzzyTestCollect {
        FuzzyTestAccept fuzzyTestAccept;
        IRecurringCollector.CollectParams collectParams;
    }

    struct FuzzyTestAccept {
        IRecurringCollector.RecurringCollectionAgreement rca;
        uint256 unboundedSignerKey;
    }

    RecurringCollector internal _recurringCollector;
    PaymentsEscrowMock internal _paymentsEscrow;
    RecurringCollectorHelper internal _recurringCollectorHelper;

    function setUp() public {
        _paymentsEscrow = new PaymentsEscrowMock();
        _recurringCollector = new RecurringCollector(
            "RecurringCollector",
            "1",
            address(new RecurringCollectorControllerMock(address(_paymentsEscrow))),
            1
        );
        _recurringCollectorHelper = new RecurringCollectorHelper(_recurringCollector);
    }

    function _sensibleAuthorizeAndAccept(
        FuzzyTestAccept calldata _fuzzyTestAccept
    ) internal returns (IRecurringCollector.SignedRCA memory, uint256 key) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _sensibleRCA(_fuzzyTestAccept.rca);
        key = boundKey(_fuzzyTestAccept.unboundedSignerKey);
        return (_authorizeAndAccept(rca, key), key);
    }

    // authorizes signer, signs the RCA, and accepts it
    function _authorizeAndAccept(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        uint256 _signerKey
    ) internal returns (IRecurringCollector.SignedRCA memory) {
        _recurringCollectorHelper.authorizeSignerWithChecks(_rca.payer, _signerKey);
        IRecurringCollector.SignedRCA memory signedRCA = _recurringCollectorHelper.generateSignedRCA(_rca, _signerKey);

        _accept(signedRCA);

        return signedRCA;
    }

    function _accept(IRecurringCollector.SignedRCA memory _signedRCA) internal {
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementAccepted(
            _signedRCA.rca.dataService,
            _signedRCA.rca.payer,
            _signedRCA.rca.serviceProvider,
            _signedRCA.rca.agreementId,
            block.timestamp,
            _signedRCA.rca.endsAt,
            _signedRCA.rca.maxInitialTokens,
            _signedRCA.rca.maxOngoingTokensPerSecond,
            _signedRCA.rca.minSecondsPerCollection,
            _signedRCA.rca.maxSecondsPerCollection
        );
        vm.prank(_signedRCA.rca.dataService);
        _recurringCollector.accept(_signedRCA);
    }

    function _cancel(IRecurringCollector.RecurringCollectionAgreement memory _rca) internal {
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementCanceled(
            _rca.dataService,
            _rca.payer,
            _rca.serviceProvider,
            _rca.agreementId,
            block.timestamp
        );
        vm.prank(_rca.dataService);
        _recurringCollector.cancel(_rca.agreementId);
    }

    function _expectCollectCallAndEmit(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        IRecurringCollector.CollectParams memory _fuzzyParams,
        uint256 _tokens
    ) internal {
        vm.expectCall(
            address(_paymentsEscrow),
            abi.encodeCall(
                _paymentsEscrow.collect,
                (
                    IGraphPayments.PaymentTypes.IndexingFee,
                    _rca.payer,
                    _rca.serviceProvider,
                    _tokens,
                    _rca.dataService,
                    _fuzzyParams.dataServiceCut
                )
            )
        );
        vm.expectEmit(address(_recurringCollector));
        emit IPaymentsCollector.PaymentCollected(
            IGraphPayments.PaymentTypes.IndexingFee,
            _fuzzyParams.collectionId,
            _rca.payer,
            _rca.serviceProvider,
            _rca.dataService,
            _tokens
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.RCACollected(
            _rca.dataService,
            _rca.payer,
            _rca.serviceProvider,
            _rca.agreementId,
            _fuzzyParams.collectionId,
            _tokens,
            _fuzzyParams.dataServiceCut
        );
    }

    function _generateValidCollection(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        IRecurringCollector.CollectParams memory _fuzzyParams,
        uint256 _unboundedCollectionSkip,
        uint256 _unboundedTokens
    ) internal view returns (bytes memory, uint256, uint256) {
        uint256 collectionSeconds = boundSkip(
            _unboundedCollectionSkip,
            _rca.minSecondsPerCollection,
            _rca.maxSecondsPerCollection
        );
        uint256 tokens = bound(_unboundedTokens, 1, _rca.maxOngoingTokensPerSecond * collectionSeconds);
        bytes memory data = _generateCollectData(
            _generateCollectParams(_rca, _fuzzyParams.collectionId, tokens, _fuzzyParams.dataServiceCut)
        );

        return (data, collectionSeconds, tokens);
    }

    function _sensibleRCA(
        IRecurringCollector.RecurringCollectionAgreement memory _rca
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        vm.assume(_rca.agreementId != bytes16(0));
        vm.assume(_rca.dataService != address(0));
        vm.assume(_rca.payer != address(0));
        vm.assume(_rca.serviceProvider != address(0));

        _rca.minSecondsPerCollection = _sensibleMinSecondsPerCollection(_rca.minSecondsPerCollection);
        _rca.maxSecondsPerCollection = _sensibleMaxSecondsPerCollection(
            _rca.maxSecondsPerCollection,
            _rca.minSecondsPerCollection
        );

        _rca.deadline = _sensibleDeadline(_rca.deadline);
        _rca.endsAt = _sensibleEndsAt(_rca.endsAt, _rca.maxSecondsPerCollection);

        _rca.maxInitialTokens = _sensibleMaxInitialTokens(_rca.maxInitialTokens);
        _rca.maxOngoingTokensPerSecond = _sensibleMaxOngoingTokensPerSecond(_rca.maxOngoingTokensPerSecond);

        return _rca;
    }

    function _sensibleRCAU(
        IRecurringCollector.RecurringCollectionAgreement memory _rca
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreementUpgrade memory) {
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau;
        rcau.agreementId = _rca.agreementId;

        rcau.minSecondsPerCollection = _sensibleMinSecondsPerCollection(_rca.minSecondsPerCollection);
        rcau.maxSecondsPerCollection = _sensibleMaxSecondsPerCollection(
            _rca.maxSecondsPerCollection,
            rcau.minSecondsPerCollection
        );

        rcau.deadline = _sensibleDeadline(_rca.deadline);
        rcau.endsAt = _sensibleEndsAt(_rca.endsAt, rcau.maxSecondsPerCollection);
        rcau.maxInitialTokens = _sensibleMaxInitialTokens(_rca.maxInitialTokens);
        rcau.maxOngoingTokensPerSecond = _sensibleMaxOngoingTokensPerSecond(_rca.maxOngoingTokensPerSecond);

        return rcau;
    }

    function _sensibleDeadline(uint256 _seed) internal view returns (uint256) {
        return bound(_seed, block.timestamp + 1, block.timestamp + 7200); // between now and 2h
    }

    function _sensibleEndsAt(uint256 _seed, uint32 _maxSecondsPerCollection) internal view returns (uint256) {
        return
            bound(
                _seed,
                block.timestamp + (10 * uint256(_maxSecondsPerCollection)),
                block.timestamp + (1_000_000 * uint256(_maxSecondsPerCollection))
            ); // between 10 and 1M max collections
    }

    function _sensibleMaxInitialTokens(uint256 _seed) internal pure returns (uint256) {
        return bound(_seed, 0, 1e18 * 100_000_000); // between 0 and 100M tokens
    }

    function _sensibleMaxOngoingTokensPerSecond(uint256 _seed) internal pure returns (uint256) {
        return bound(_seed, 1, 1e18); // between 1 and 1e18 tokens per second
    }

    function _sensibleMinSecondsPerCollection(uint32 _seed) internal pure returns (uint32) {
        return uint32(bound(_seed, 10 * 60, 24 * 60 * 60)); // between 10 min and 24h
    }

    function _sensibleMaxSecondsPerCollection(
        uint32 _seed,
        uint32 _minSecondsPerCollection
    ) internal pure returns (uint32) {
        return
            uint32(
                bound(_seed, _minSecondsPerCollection + 7200, 60 * 60 * 24 * 30) // between minSecondsPerCollection + 2h and 30 days
            );
    }

    // Do I need this?
    function _generateCollectParams(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        bytes32 _collectionId,
        uint256 _tokens,
        uint256 _dataServiceCut
    ) internal pure returns (IRecurringCollector.CollectParams memory) {
        return
            IRecurringCollector.CollectParams({
                agreementId: _rca.agreementId,
                collectionId: _collectionId,
                tokens: _tokens,
                dataServiceCut: _dataServiceCut
            });
    }

    function _generateCollectData(
        IRecurringCollector.CollectParams memory _params
    ) internal pure returns (bytes memory) {
        return abi.encode(_params);
    }
}

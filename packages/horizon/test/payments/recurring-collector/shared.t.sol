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
    struct TestCollectParams {
        IRecurringCollector.CollectParams collectData;
        address dataService;
    }

    struct FuzzyAcceptableRCA {
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

    function _fuzzyAuthorizeAndAccept(
        FuzzyAcceptableRCA memory _fuzzyAcceptableRCA
    ) internal returns (IRecurringCollector.SignedRCA memory) {
        _fuzzyAcceptableRCA.rca = _sensibleRCA(_fuzzyAcceptableRCA.rca);
        _fuzzyAcceptableRCA.rca = _recurringCollectorHelper.withOKAcceptDeadline(_fuzzyAcceptableRCA.rca);
        return _authorizeAndAcceptV2(_fuzzyAcceptableRCA.rca, boundKey(_fuzzyAcceptableRCA.unboundedSignerKey));
    }

    function _authorizeAndAccept(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        uint256 _signerKey
    ) internal returns (IRecurringCollector.SignedRCA memory) {
        vm.assume(_rca.payer != address(0));
        _rca.deadline = boundTimestampMin(_rca.deadline, block.timestamp + 1);
        return _authorizeAndAcceptV2(_rca, _signerKey);
    }

    function _authorizeAndAcceptV2(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        uint256 _signerKey
    ) internal returns (IRecurringCollector.SignedRCA memory) {
        _recurringCollectorHelper.authorizeSignerWithChecks(_rca.payer, _signerKey);
        IRecurringCollector.SignedRCA memory signedRCA = _recurringCollectorHelper.generateSignedRCA(_rca, _signerKey);

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementAccepted(
            _rca.dataService,
            _rca.payer,
            _rca.serviceProvider,
            _rca.agreementId,
            block.timestamp,
            _rca.duration,
            _rca.maxInitialTokens,
            _rca.maxOngoingTokensPerSecond,
            _rca.minSecondsPerCollection,
            _rca.maxSecondsPerCollection
        );
        vm.prank(_rca.dataService);
        _recurringCollector.accept(signedRCA);

        return signedRCA;
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
    ) internal pure returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        vm.assume(_rca.dataService != address(0));
        vm.assume(_rca.payer != address(0));
        vm.assume(_rca.serviceProvider != address(0));
        _rca.minSecondsPerCollection = uint32(bound(_rca.minSecondsPerCollection, 60, 60 * 60 * 24));
        _rca.maxSecondsPerCollection = uint32(
            bound(_rca.maxSecondsPerCollection, _rca.minSecondsPerCollection + 7200, 60 * 60 * 24 * 30)
        );
        _rca.duration = bound(_rca.duration, _rca.maxSecondsPerCollection * 10, type(uint256).max);
        _rca.maxInitialTokens = bound(_rca.maxInitialTokens, 0, 1e18 * 100_000_000);
        _rca.maxOngoingTokensPerSecond = bound(_rca.maxOngoingTokensPerSecond, 1, 1e18);

        return _rca;
    }

    function _sensibleRCAU(
        IRecurringCollector.RecurringCollectionAgreement memory _rca
    ) internal pure returns (IRecurringCollector.RecurringCollectionAgreementUpgrade memory) {
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau;
        rcau.agreementId = _rca.agreementId;
        rcau.minSecondsPerCollection = uint32(bound(_rca.minSecondsPerCollection, 60, 60 * 60 * 24));
        rcau.maxSecondsPerCollection = uint32(
            bound(_rca.maxSecondsPerCollection, rcau.minSecondsPerCollection * 2, 60 * 60 * 24 * 30)
        );
        rcau.duration = bound(_rca.duration, rcau.maxSecondsPerCollection * 10, type(uint256).max);
        rcau.maxInitialTokens = bound(_rca.maxInitialTokens, 0, 1e18 * 100_000_000);
        rcau.maxOngoingTokensPerSecond = bound(_rca.maxOngoingTokensPerSecond, 1, 1e18);

        return rcau;
    }

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

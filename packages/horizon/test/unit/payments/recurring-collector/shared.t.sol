// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { IGraphPayments } from "../../../../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsCollector } from "../../../../contracts/interfaces/IPaymentsCollector.sol";
import { IRecurringCollector } from "../../../../contracts/interfaces/IRecurringCollector.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";

import { Bounder } from "../../../unit/utils/Bounder.t.sol";
import { PartialControllerMock } from "../../mocks/PartialControllerMock.t.sol";
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

    struct FuzzyTestUpdate {
        FuzzyTestAccept fuzzyTestAccept;
        IRecurringCollector.RecurringCollectionAgreementUpdate rcau;
    }

    RecurringCollector internal _recurringCollector;
    PaymentsEscrowMock internal _paymentsEscrow;
    RecurringCollectorHelper internal _recurringCollectorHelper;

    function setUp() public {
        _paymentsEscrow = new PaymentsEscrowMock();
        PartialControllerMock.Entry[] memory entries = new PartialControllerMock.Entry[](1);
        entries[0] = PartialControllerMock.Entry({ name: "PaymentsEscrow", addr: address(_paymentsEscrow) });
        _recurringCollector = new RecurringCollector(
            "RecurringCollector",
            "1",
            address(new PartialControllerMock(entries)),
            1
        );
        _recurringCollectorHelper = new RecurringCollectorHelper(_recurringCollector);
    }

    function _sensibleAuthorizeAndAccept(
        FuzzyTestAccept calldata _fuzzyTestAccept
    ) internal returns (IRecurringCollector.SignedRCA memory, uint256 key) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            _fuzzyTestAccept.rca
        );
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
            uint64(block.timestamp),
            _signedRCA.rca.endsAt,
            _signedRCA.rca.maxInitialTokens,
            _signedRCA.rca.maxOngoingTokensPerSecond,
            _signedRCA.rca.minSecondsPerCollection,
            _signedRCA.rca.maxSecondsPerCollection
        );
        vm.prank(_signedRCA.rca.dataService);
        _recurringCollector.accept(_signedRCA);
    }

    function _cancel(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        IRecurringCollector.CancelAgreementBy _by
    ) internal {
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementCanceled(
            _rca.dataService,
            _rca.payer,
            _rca.serviceProvider,
            _rca.agreementId,
            uint64(block.timestamp),
            _by
        );
        vm.prank(_rca.dataService);
        _recurringCollector.cancel(_rca.agreementId, _by);
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
                    _fuzzyParams.dataServiceCut,
                    _rca.serviceProvider
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
                dataServiceCut: _dataServiceCut,
                receiverDestination: _rca.serviceProvider
            });
    }

    function _generateCollectData(
        IRecurringCollector.CollectParams memory _params
    ) internal pure returns (bytes memory) {
        return abi.encode(_params);
    }

    function _fuzzyCancelAgreementBy(uint8 _seed) internal pure returns (IRecurringCollector.CancelAgreementBy) {
        return
            IRecurringCollector.CancelAgreementBy(
                bound(_seed, 0, uint256(IRecurringCollector.CancelAgreementBy.Payer))
            );
    }
}

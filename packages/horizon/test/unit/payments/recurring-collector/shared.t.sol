// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { IGraphPayments } from "../../../../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsCollector } from "../../../../contracts/interfaces/IPaymentsCollector.sol";
import { IRecurringCollector } from "../../../../contracts/interfaces/IRecurringCollector.sol";
import { IHorizonStakingTypes } from "../../../../contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";

import { Bounder } from "../../../unit/utils/Bounder.t.sol";
import { PartialControllerMock } from "../../mocks/PartialControllerMock.t.sol";
import { HorizonStakingMock } from "../../mocks/HorizonStakingMock.t.sol";
import { PaymentsEscrowMock } from "./PaymentsEscrowMock.t.sol";
import { RecurringCollectorHelper } from "./RecurringCollectorHelper.t.sol";

contract RecurringCollectorSharedTest is Test, Bounder {
    struct FuzzyTestCollect {
        FuzzyTestAccept fuzzyTestAccept;
        uint8 unboundedPaymentType;
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
    HorizonStakingMock internal _horizonStaking;
    RecurringCollectorHelper internal _recurringCollectorHelper;

    function setUp() public {
        _paymentsEscrow = new PaymentsEscrowMock();
        _horizonStaking = new HorizonStakingMock();
        PartialControllerMock.Entry[] memory entries = new PartialControllerMock.Entry[](2);
        entries[0] = PartialControllerMock.Entry({ name: "PaymentsEscrow", addr: address(_paymentsEscrow) });
        entries[1] = PartialControllerMock.Entry({ name: "Staking", addr: address(_horizonStaking) });
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
    ) internal returns (IRecurringCollector.SignedRCA memory, uint256 key, bytes16 agreementId) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            _fuzzyTestAccept.rca
        );
        key = boundKey(_fuzzyTestAccept.unboundedSignerKey);
        IRecurringCollector.SignedRCA memory signedRCA;
        (signedRCA, agreementId) = _authorizeAndAccept(rca, key);
        return (signedRCA, key, agreementId);
    }

    // authorizes signer, signs the RCA, and accepts it
    function _authorizeAndAccept(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        uint256 _signerKey
    ) internal returns (IRecurringCollector.SignedRCA memory, bytes16 agreementId) {
        _recurringCollectorHelper.authorizeSignerWithChecks(_rca.payer, _signerKey);
        IRecurringCollector.SignedRCA memory signedRCA = _recurringCollectorHelper.generateSignedRCA(_rca, _signerKey);

        agreementId = _accept(signedRCA);
        return (signedRCA, agreementId);
    }

    function _accept(IRecurringCollector.SignedRCA memory _signedRCA) internal returns (bytes16) {
        // Set up valid staking provision by default to allow collections to succeed
        _setupValidProvision(_signedRCA.rca.serviceProvider, _signedRCA.rca.dataService);

        // Calculate the expected agreement ID for verification
        bytes16 expectedAgreementId = _recurringCollector.generateAgreementId(
            _signedRCA.rca.payer,
            _signedRCA.rca.dataService,
            _signedRCA.rca.serviceProvider,
            _signedRCA.rca.deadline,
            _signedRCA.rca.nonce
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementAccepted(
            _signedRCA.rca.dataService,
            _signedRCA.rca.payer,
            _signedRCA.rca.serviceProvider,
            expectedAgreementId,
            uint64(block.timestamp),
            _signedRCA.rca.endsAt,
            _signedRCA.rca.maxInitialTokens,
            _signedRCA.rca.maxOngoingTokensPerSecond,
            _signedRCA.rca.minSecondsPerCollection,
            _signedRCA.rca.maxSecondsPerCollection
        );
        vm.prank(_signedRCA.rca.dataService);
        bytes16 actualAgreementId = _recurringCollector.accept(_signedRCA);

        // Verify the agreement ID matches expectation
        assertEq(actualAgreementId, expectedAgreementId);
        return actualAgreementId;
    }

    function _setupValidProvision(address _serviceProvider, address _dataService) internal {
        _horizonStaking.setProvision(
            _serviceProvider,
            _dataService,
            IHorizonStakingTypes.Provision({
                tokens: 1000 ether,
                tokensThawing: 0,
                sharesThawing: 0,
                maxVerifierCut: 100000, // 10%
                thawingPeriod: 604800, // 7 days
                createdAt: uint64(block.timestamp),
                maxVerifierCutPending: 100000,
                thawingPeriodPending: 604800,
                lastParametersStagedAt: 0,
                thawingNonce: 0
            })
        );
    }

    function _cancel(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        bytes16 _agreementId,
        IRecurringCollector.CancelAgreementBy _by
    ) internal {
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementCanceled(
            _rca.dataService,
            _rca.payer,
            _rca.serviceProvider,
            _agreementId,
            uint64(block.timestamp),
            _by
        );
        vm.prank(_rca.dataService);
        _recurringCollector.cancel(_agreementId, _by);
    }

    function _expectCollectCallAndEmit(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        bytes16 _agreementId,
        IGraphPayments.PaymentTypes __paymentType,
        IRecurringCollector.CollectParams memory _fuzzyParams,
        uint256 _tokens
    ) internal {
        vm.expectCall(
            address(_paymentsEscrow),
            abi.encodeCall(
                _paymentsEscrow.collect,
                (
                    __paymentType,
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
            __paymentType,
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
            _agreementId,
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

        // Generate the agreement ID deterministically
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            _rca.payer,
            _rca.dataService,
            _rca.serviceProvider,
            _rca.deadline,
            _rca.nonce
        );

        bytes memory data = _generateCollectData(
            _generateCollectParams(_rca, agreementId, _fuzzyParams.collectionId, tokens, _fuzzyParams.dataServiceCut)
        );

        return (data, collectionSeconds, tokens);
    }

    function _generateCollectParams(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        bytes16 _agreementId,
        bytes32 _collectionId,
        uint256 _tokens,
        uint256 _dataServiceCut
    ) internal pure returns (IRecurringCollector.CollectParams memory) {
        return
            IRecurringCollector.CollectParams({
                agreementId: _agreementId,
                collectionId: _collectionId,
                tokens: _tokens,
                dataServiceCut: _dataServiceCut,
                receiverDestination: _rca.serviceProvider,
                maxSlippage: type(uint256).max
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

    function _paymentType(uint8 _unboundedPaymentType) internal pure returns (IGraphPayments.PaymentTypes) {
        return
            IGraphPayments.PaymentTypes(
                bound(
                    _unboundedPaymentType,
                    uint256(type(IGraphPayments.PaymentTypes).min),
                    uint256(type(IGraphPayments.PaymentTypes).max)
                )
            );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PAYER,
    BY_PROVIDER,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { Bounder } from "../../../unit/utils/Bounder.t.sol";
import { PartialControllerMock } from "../../mocks/PartialControllerMock.t.sol";
import { HorizonStakingMock } from "../../mocks/HorizonStakingMock.t.sol";
import { PaymentsEscrowMock } from "./PaymentsEscrowMock.t.sol";
import { RecurringCollectorHelper } from "./RecurringCollectorHelper.t.sol";
import { MockAcceptCallback } from "./MockAcceptCallback.t.sol";

contract RecurringCollectorSharedTest is Test, Bounder {
    struct FuzzyTestCollect {
        FuzzyTestAccept fuzzyTestAccept;
        uint8 unboundedPaymentType;
        IRecurringCollector.CollectParams collectParams;
    }

    struct FuzzyTestAccept {
        IRecurringCollector.RecurringCollectionAgreement rca;
    }

    struct FuzzyTestUpdate {
        FuzzyTestAccept fuzzyTestAccept;
        IRecurringCollector.RecurringCollectionAgreementUpdate rcau;
    }

    RecurringCollector internal _recurringCollector;
    PaymentsEscrowMock internal _paymentsEscrow;
    HorizonStakingMock internal _horizonStaking;
    RecurringCollectorHelper internal _recurringCollectorHelper;
    address internal _proxyAdmin;
    bytes internal _mockAcceptCallbackCode;

    function setUp() public virtual {
        _paymentsEscrow = new PaymentsEscrowMock();
        _horizonStaking = new HorizonStakingMock();
        PartialControllerMock.Entry[] memory entries = new PartialControllerMock.Entry[](2);
        entries[0] = PartialControllerMock.Entry({ name: "PaymentsEscrow", addr: address(_paymentsEscrow) });
        entries[1] = PartialControllerMock.Entry({ name: "Staking", addr: address(_horizonStaking) });
        address controller = address(new PartialControllerMock(entries));
        RecurringCollector implementation = new RecurringCollector(controller);
        address proxyAdminOwner = makeAddr("proxyAdminOwner");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            proxyAdminOwner,
            abi.encodeCall(RecurringCollector.initialize, ())
        );
        _recurringCollector = RecurringCollector(address(proxy));
        // Store the actual ProxyAdmin contract address to exclude from fuzz inputs
        _proxyAdmin = address(uint160(uint256(vm.load(address(proxy), ERC1967Utils.ADMIN_SLOT))));
        _recurringCollectorHelper = new RecurringCollectorHelper(_recurringCollector, _proxyAdmin);
        _mockAcceptCallbackCode = address(new MockAcceptCallback()).code;
    }

    function _sensibleAccept(
        FuzzyTestAccept calldata _fuzzyTestAccept
    ) internal returns (IRecurringCollector.RecurringCollectionAgreement memory, bytes16 agreementId) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            _fuzzyTestAccept.rca
        );
        agreementId = _accept(rca);
        return (rca, agreementId);
    }

    function _accept(IRecurringCollector.RecurringCollectionAgreement memory _rca) internal returns (bytes16) {
        // Set up valid staking provision by default to allow collections to succeed
        _setupValidProvision(_rca.serviceProvider, _rca.dataService);

        // Calculate the expected agreement ID for verification
        bytes16 expectedAgreementId = _recurringCollector.generateAgreementId(
            _rca.payer,
            _rca.dataService,
            _rca.serviceProvider,
            _rca.deadline,
            _rca.nonce
        );

        // Step 1: Payer submits offer
        vm.prank(_rca.payer);
        bytes16 actualAgreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(_rca), 0).agreementId;

        // Verify the agreement ID matches expectation
        assertEq(actualAgreementId, expectedAgreementId);

        // Step 2: Service provider accepts the offer
        bytes32 activeHash = _recurringCollector.getAgreementDetails(actualAgreementId, 0).versionHash;
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(expectedAgreementId, activeHash, REGISTERED | ACCEPTED);
        vm.prank(_rca.serviceProvider);
        _recurringCollector.accept(actualAgreementId, activeHash, bytes(""), 0);

        return actualAgreementId;
    }

    function _offer(IRecurringCollector.RecurringCollectionAgreement memory _rca) internal returns (bytes16) {
        _setupValidProvision(_rca.serviceProvider, _rca.dataService);
        vm.prank(_rca.payer);
        return _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(_rca), 0).agreementId;
    }

    function _sensibleOffer(
        FuzzyTestAccept calldata _fuzzyTestAccept
    ) internal returns (IRecurringCollector.RecurringCollectionAgreement memory, bytes16 agreementId) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            _fuzzyTestAccept.rca
        );
        agreementId = _offer(rca);
        return (rca, agreementId);
    }

    function _setupValidProvision(address _serviceProvider, address _dataService) internal {
        // In RC unit tests, dataService must be a fresh address so we can etch mock callback code.
        // Reject fuzz inputs that collide with deployed test infrastructure.
        vm.assume(_dataService.code.length == 0);
        // Etch mock IDataServiceAgreements code so accept/acceptUpdate callbacks succeed.
        if (uint160(_dataService) > 0xFF) {
            vm.etch(_dataService, _mockAcceptCallbackCode);
        }
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

    function _cancelByPayer(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        bytes16 _agreementId
    ) internal {
        bytes32 vHash = _recurringCollector.getAgreementDetails(_agreementId, 0).versionHash;
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(_agreementId, vHash, REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PAYER);
        vm.prank(_rca.payer);
        _recurringCollector.cancel(_agreementId, vHash, 0);
    }

    function _cancelByProvider(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        bytes16 _agreementId
    ) internal {
        bytes32 vHash = _recurringCollector.getAgreementDetails(_agreementId, 0).versionHash;
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(
            _agreementId,
            vHash,
            REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PROVIDER
        );
        vm.prank(_rca.serviceProvider);
        _recurringCollector.cancel(_agreementId, vHash, 0);
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
        emit IRecurringCollector.RCACollected(_agreementId, _fuzzyParams.collectionId, REGISTERED | ACCEPTED);
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

    function _fuzzyCancelByPayer(uint8 _seed) internal pure returns (bool) {
        return bound(_seed, 0, 1) == 1;
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

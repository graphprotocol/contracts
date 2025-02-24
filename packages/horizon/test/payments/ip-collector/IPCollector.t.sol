// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { ControllerMock } from "../../../contracts/mocks/ControllerMock.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsEscrow } from "../../../contracts/interfaces/IPaymentsEscrow.sol";
import { IAuthorizable } from "../../../contracts/interfaces/IAuthorizable.sol";
import { IIPCollector } from "../../../contracts/interfaces/IIPCollector.sol";
import { IPCollector } from "../../../contracts/payments/collectors/IPCollector.sol";
import { AuthorizableTest, AuthorizableHelper } from "../../utilities/Authorizable.t.sol";
import { Bounder } from "../../utils/Bounder.t.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Controller is ControllerMock, Test {
    address invalidContractAddress;
    IPaymentsEscrow paymentsEscrow;

    constructor() ControllerMock(address(0)) {
        invalidContractAddress = makeAddr("invalidContractAddress");
        paymentsEscrow = new PaymentsEscrow();
    }

    function getContractProxy(bytes32 _b) external view override returns (address) {
        return _b == keccak256("PaymentsEscrow") ? address(paymentsEscrow) : invalidContractAddress;
    }
}

contract PaymentsEscrow is IPaymentsEscrow, Test {
    function collect(IGraphPayments.PaymentTypes, address, address, uint256, address, uint256) external {}

    function deposit(address, address, uint256) external {}

    function depositTo(address, address, address, uint256) external {}

    function thaw(address, address, uint256) external {}

    function cancelThaw(address, address) external {}

    function withdraw(address, address) external {}

    function getBalance(address, address, address) external pure returns (uint256) {
        return 0;
    }
}

contract IPCollectorAuthorizableTest is AuthorizableTest {
    function newAuthorizable(uint256 _thawPeriod) public override returns (IAuthorizable) {
        return new IPCollector("IPCollector", "1", address(new Controller()), _thawPeriod);
    }
}

contract IPCollectorTest is Test, Bounder {
    IPCollector ipCollector;
    AuthorizableHelper authHelper;

    function setUp() public {
        ipCollector = new IPCollector("IPCollector", "1", address(new Controller()), 1);
        authHelper = new AuthorizableHelper(ipCollector, 1);
    }

    function test_Accept(IIPCollector.IndexingAgreementVoucher memory _iav, uint256 _unboundedKey) public {
        _authorizeAndAccept(_iav, boundKey(_unboundedKey));
    }

    function test_Cancel(IIPCollector.IndexingAgreementVoucher memory _iav, uint256 _unboundedKey) public {
        _authorizeAndAccept(_iav, boundKey(_unboundedKey));
        _cancel(_iav);
    }

    function _cancel(IIPCollector.IndexingAgreementVoucher memory _iav) private {
        vm.prank(_iav.dataService);
        ipCollector.cancel(_iav.payer, _iav.serviceProvider, _iav.agreementId);
    }

    function test_Cancel_Revert_WhenNotAccepted(IIPCollector.IndexingAgreementVoucher memory _iav) public {
        vm.expectRevert("IPCollectorInvalidAgreementId");
        ipCollector.cancel(_iav.payer, _iav.serviceProvider, _iav.agreementId);
    }

    function test_Cancel_Revert_WhenNotDataService(
        IIPCollector.IndexingAgreementVoucher memory _iav,
        address _notDataService,
        uint256 _unboundedKey
    ) public {
        vm.assume(_iav.dataService != _notDataService);

        _authorizeAndAccept(_iav, boundKey(_unboundedKey));
        vm.expectRevert("IPCollectorInvalidAgreementId");
        vm.prank(_notDataService);
        ipCollector.cancel(_iav.payer, _iav.serviceProvider, _iav.agreementId);
    }

    function _authorizeAndAccept(IIPCollector.IndexingAgreementVoucher memory _iav, uint256 _signerKey) private {
        vm.assume(_iav.payer != address(0));
        authHelper.authorizeSignerWithChecks(_iav.payer, _signerKey);
        IIPCollector.SignedIAV memory signedIAV = _generateSignedIAV(ipCollector, _iav, _signerKey);

        vm.prank(_iav.dataService);
        ipCollector.accept(signedIAV);
    }

    function test_Collect_Revert_WhenInvalidPaymentType(uint8 _unboundedPaymentType, bytes memory _data) public {
        uint256 lastPaymentType = uint256(IGraphPayments.PaymentTypes.IndexingRewards);

        IGraphPayments.PaymentTypes _paymentType = IGraphPayments.PaymentTypes(
            bound(_unboundedPaymentType, 0, lastPaymentType)
        );
        vm.assume(_paymentType != IGraphPayments.PaymentTypes.IndexingFee);

        bytes memory expectedErr = abi.encodeWithSelector(
            IIPCollector.IPCollectorInvalidPaymentType.selector,
            _paymentType
        );
        vm.expectRevert(expectedErr);
        ipCollector.collect(_paymentType, _data);

        // If I move this to the top of the function, the rest of the test does not run. Not sure why...
        {
            vm.expectRevert();
            IGraphPayments.PaymentTypes(lastPaymentType + 1);
        }
    }

    function test_Collect_Revert_WhenInvalidData(address _caller, bytes memory _data) public {
        vm.expectRevert("IPCollectorInvalidCollectData");
        vm.prank(_caller);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, _data);
    }

    function test_Collect_Revert_WhenCallerNotDataService(
        IIPCollector.CollectParams memory _params,
        address _notDataService
    ) public {
        vm.assume(_params.key.dataService != _notDataService);

        bytes memory data = _generateCollectData(_params);

        bytes memory expectedErr = abi.encodeWithSelector(
            IIPCollector.IPCollectorCallerNotDataService.selector,
            _notDataService,
            _params.key.dataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(_notDataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenUnknownAgreement(IIPCollector.CollectParams memory _params) public {
        bytes memory data = _generateCollectData(_params);

        vm.expectRevert("IPCollectorInvalidAgreementId");
        vm.prank(_params.key.dataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCanceledAgreement(
        IIPCollector.IndexingAgreementVoucher memory _iav,
        IIPCollector.CollectParams memory _fuzzyParams,
        uint256 _unboundedKey
    ) public {
        _authorizeAndAccept(_iav, boundKey(_unboundedKey));
        _cancel(_iav);
        bytes memory data = _generateCollectData(
            _generateCollectParams(_iav, _fuzzyParams.collectionId, _fuzzyParams.tokens, _fuzzyParams.dataServiceCut)
        );

        vm.expectRevert("IPCollectorInvalidAgreementId");
        vm.prank(_iav.dataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenAgreementElapsed(
        IIPCollector.IndexingAgreementVoucher memory _iav,
        IIPCollector.CollectParams memory _fuzzyParams,
        uint256 _unboundedKey,
        uint256 _unboundedAcceptAt,
        uint256 _unboundedCollectAt
    ) public {
        _iav = _sensibleIAV(_iav);
        skip(boundSkipMax(_unboundedAcceptAt, type(uint256).max - block.timestamp - 1)); // allow for proofdeadline to be valid
        _authorizeAndAccept(_iav, boundKey(_unboundedKey));
        bytes memory data = _generateCollectData(
            _generateCollectParams(_iav, _fuzzyParams.collectionId, _fuzzyParams.tokens, _fuzzyParams.dataServiceCut)
        );

        skip(boundSkipMin(_unboundedCollectAt, _iav.duration));
        vm.expectRevert("IPCollectorAgreementElapsed");
        vm.prank(_iav.dataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooSoon(
        IIPCollector.IndexingAgreementVoucher memory _iav,
        IIPCollector.CollectParams memory _fuzzyParams,
        uint256 _unboundedKey,
        uint256 _unboundedSkip
    ) public {
        _iav = _sensibleIAV(_iav);
        _authorizeAndAccept(_iav, boundKey(_unboundedKey));

        skip(_iav.minSecondsPerCollection);
        bytes memory data = _generateCollectData(
            _generateCollectParams(_iav, _fuzzyParams.collectionId, 1, _fuzzyParams.dataServiceCut)
        );
        vm.prank(_iav.dataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);

        skip(boundSkipMax(_unboundedSkip, _iav.minSecondsPerCollection - 1));
        data = _generateCollectData(
            _generateCollectParams(_iav, _fuzzyParams.collectionId, _fuzzyParams.tokens, _fuzzyParams.dataServiceCut)
        );
        vm.expectRevert("IPCollectorCollectionTooSoon");
        vm.prank(_iav.dataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function _sensibleIAV(
        IIPCollector.IndexingAgreementVoucher memory _iav
    ) private pure returns (IIPCollector.IndexingAgreementVoucher memory) {
        _iav.minSecondsPerCollection = uint32(bound(_iav.minSecondsPerCollection, 60, 60 * 60 * 24));
        _iav.maxSecondsPerCollection = uint32(
            bound(_iav.maxSecondsPerCollection, _iav.minSecondsPerCollection, 60 * 60 * 24 * 30)
        );
        _iav.duration = bound(_iav.duration, (_iav.minSecondsPerCollection * 100) + 1, type(uint256).max);
        _iav.maxInitialTokens = bound(_iav.maxInitialTokens, 0, 1e18 * 100_000_000);
        _iav.maxOngoingTokensPerSecond = bound(_iav.maxOngoingTokensPerSecond, 1, 1e18);

        return _iav;
    }

    function _generateCollectParams(
        IIPCollector.IndexingAgreementVoucher memory _iav,
        bytes32 _collectionId,
        uint256 _tokens,
        uint256 _dataServiceCut
    ) private pure returns (IIPCollector.CollectParams memory) {
        return
            IIPCollector.CollectParams({
                key: IIPCollector.AgreementKey({
                    dataService: _iav.dataService,
                    payer: _iav.payer,
                    serviceProvider: _iav.serviceProvider,
                    agreementId: _iav.agreementId
                }),
                collectionId: _collectionId,
                tokens: _tokens,
                dataServiceCut: _dataServiceCut
            });
    }

    function _generateSignedIAV(
        IIPCollector _ipCollector,
        IIPCollector.IndexingAgreementVoucher memory iav,
        uint256 _signerPrivateKey
    ) private view returns (IIPCollector.SignedIAV memory) {
        bytes32 messageHash = _ipCollector.encodeIAV(iav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IIPCollector.SignedIAV memory signedIAV = IIPCollector.SignedIAV({ iav: iav, signature: signature });

        return signedIAV;
    }

    function _generateCollectData(IIPCollector.CollectParams memory _params) private pure returns (bytes memory) {
        return abi.encode(_params);
    }
}

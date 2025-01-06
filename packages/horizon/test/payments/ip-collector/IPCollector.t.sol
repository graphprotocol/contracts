// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { ControllerMock } from "../../../contracts/mocks/ControllerMock.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IIPCollector } from "../../../contracts/interfaces/IIPCollector.sol";
import { IPCollector } from "../../../contracts/payments/collectors/IPCollector.sol";
import { AuthorizableTest, AuthorizableHelper } from "../../utilities/Authorizable.t.sol";
import { Bounder } from "../../utils/Bounder.t.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Controller is ControllerMock, Test {
    address invalidContractAddress;

    constructor() ControllerMock(address(0)) {
        invalidContractAddress = makeAddr("invalidContractAddress");
    }

    function getContractProxy(bytes32) external view override returns (address) {
        return invalidContractAddress;
    }
}

contract IPCollectorAuthorizableTest is AuthorizableTest {
    function setUp() public override {
        setupAuthorizable(new IPCollector("IPCollector", "1", address(new Controller()), 1));
    }
}

contract IPCollectorTest is Test, Bounder {
    IPCollector ipCollector;
    AuthorizableHelper authHelper;

    function setUp() public {
        ipCollector = new IPCollector("IPCollector", "1", address(new Controller()), 1);
        authHelper = new AuthorizableHelper(ipCollector);
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

    function test_Collect_Revert_WhenCallerNotDataService(
        address _payer,
        address _dataService,
        address _serviceProvider,
        bytes memory _metadata,
        bytes memory _signature,
        address _notDataService,
        uint256 _dataServiceCut
    ) public {
        vm.assume(_dataService != _notDataService);

        IIPCollector.SignedIAV memory signedIAV = IIPCollector.SignedIAV({
            iav: IIPCollector.IndexingAgreementVoucher({
                payer: _payer,
                dataService: _dataService,
                serviceProvider: _serviceProvider,
                metadata: _metadata
            }),
            signature: _signature
        });
        bytes memory data = __generateCollectData(signedIAV, _dataServiceCut);

        bytes memory expectedErr = abi.encodeWithSelector(
            IIPCollector.IPCollectorCallerNotDataService.selector,
            _notDataService,
            _dataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(_notDataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenInvalidSignatureLength(
        address _payer,
        address _dataService,
        address _serviceProvider,
        bytes memory _metadata,
        bytes memory _signature,
        uint256 _dataServiceCut
    ) public {
        vm.assume(_signature.length != 65);
        IIPCollector.SignedIAV memory signedIAV = IIPCollector.SignedIAV({
            iav: IIPCollector.IndexingAgreementVoucher({
                payer: _payer,
                dataService: _dataService,
                serviceProvider: _serviceProvider,
                metadata: _metadata
            }),
            signature: _signature
        });
        bytes memory data = __generateCollectData(signedIAV, _dataServiceCut);

        bytes memory expectedErr = abi.encodeWithSelector(
            ECDSA.ECDSAInvalidSignatureLength.selector,
            _signature.length
        );
        vm.expectRevert(expectedErr);

        vm.prank(_dataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenInvalidIAVSigner(
        address _payer,
        address _dataService,
        address _serviceProvider,
        bytes memory _metadata,
        uint256 _unboundedSignerPrivateKey,
        uint256 _dataServiceCut
    ) public {
        uint256 _signerPrivateKey = boundKey(_unboundedSignerPrivateKey);
        // _signerPrivateKey is not authorized
        IIPCollector.SignedIAV memory signedIAV = _generateSignedIAV(
            ipCollector,
            IIPCollector.IndexingAgreementVoucher({
                payer: _payer,
                dataService: _dataService,
                serviceProvider: _serviceProvider,
                metadata: _metadata
            }),
            _signerPrivateKey
        );
        bytes memory data = __generateCollectData(signedIAV, _dataServiceCut);

        vm.expectRevert(IIPCollector.IPCollectorInvalidIAVSigner.selector);
        vm.prank(_dataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenNotImplemented(
        address _dataService,
        address _serviceProvider,
        bytes memory _metadata,
        uint256 _unboundedSignerPrivateKey,
        uint256 _dataServiceCut
    ) public {
        uint256 signerPrivateKey = boundKey(_unboundedSignerPrivateKey);
        address signer = vm.addr(signerPrivateKey);
        authHelper.authorizeSignerWithChecks(signer, signerPrivateKey);
        IIPCollector.SignedIAV memory signedIAV = _generateSignedIAV(
            ipCollector,
            IIPCollector.IndexingAgreementVoucher({
                payer: signer,
                dataService: _dataService,
                serviceProvider: _serviceProvider,
                metadata: _metadata
            }),
            signerPrivateKey
        );
        bytes memory data = __generateCollectData(signedIAV, _dataServiceCut);

        vm.expectRevert("Not implemented");
        vm.prank(_dataService);
        ipCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function _generateCollectData(
        IIPCollector _ipCollector,
        IIPCollector.IndexingAgreementVoucher memory iav,
        uint256 signerPrivateKey,
        uint256 dataServiceCut
    ) private view returns (bytes memory) {
        return __generateCollectData(_generateSignedIAV(_ipCollector, iav, signerPrivateKey), dataServiceCut);
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

    function __generateCollectData(
        IIPCollector.SignedIAV memory signedIAV,
        uint256 dataServiceCut
    ) private pure returns (bytes memory) {
        return abi.encode(signedIAV, dataServiceCut);
    }
}

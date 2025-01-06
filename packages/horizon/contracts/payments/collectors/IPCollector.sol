// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { Authorizable } from "../../utilities/Authorizable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { IIPCollector } from "../../interfaces/IIPCollector.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title IPCollector contract
 * @dev Implements the {IIPCollector} interface.
 * @notice A payments collector contract that can be used to collect payments using an IAV (Indexing Agreement Voucher).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract IPCollector is EIP712, GraphDirectory, Authorizable, IIPCollector {
    using PPMMath for uint256;

    /// @notice The EIP712 typehash for the IndexingAgreementVoucher struct
    bytes32 private constant EIP712_IAV_TYPEHASH =
        keccak256("IndexingAgreementVoucher(address dataService,address serviceProvider,bytes metadata)");

    /**
     * @notice Constructs a new instance of the IPCollector contract.
     * @param _eip712Name The name of the EIP712 domain.
     * @param _eip712Version The version of the EIP712 domain.
     * @param _controller The address of the Graph controller.
     * @param _revokeSignerThawingPeriod The duration (in seconds) in which a signer is thawing before they can be revoked.
     */
    constructor(
        string memory _eip712Name,
        string memory _eip712Version,
        address _controller,
        uint256 _revokeSignerThawingPeriod
    ) EIP712(_eip712Name, _eip712Version) GraphDirectory(_controller) Authorizable(_revokeSignerThawingPeriod) {}

    /**
     * @notice Initiate a payment collection through the payments protocol.
     * See {IGraphPayments.collect}.
     * @dev Caller must be the data service the IAV was issued to.
     * @dev The signer of the IAV must be authorized.
     * @notice REVERT: This function may revert if ECDSA.recover fails, check ECDSA library for details.
     */
    function collect(IGraphPayments.PaymentTypes _paymentType, bytes calldata _data) external view returns (uint256) {
        require(_paymentType == IGraphPayments.PaymentTypes.IndexingFee, IPCollectorInvalidPaymentType(_paymentType));

        (SignedIAV memory signedIAV, uint256 dataServiceCut) = abi.decode(_data, (SignedIAV, uint256));
        require(
            signedIAV.iav.dataService == msg.sender,
            IPCollectorCallerNotDataService(msg.sender, signedIAV.iav.dataService)
        );

        address signer = _recoverIAVSigner(signedIAV);
        address payer = signedIAV.iav.payer;
        require(_isAuthorized(payer, signer), IPCollectorInvalidIAVSigner());

        return _collect(signedIAV.iav, dataServiceCut);
    }

    function _collect(IndexingAgreementVoucher memory, uint256) private pure returns (uint256) {
        revert("Not implemented");
    }

    /**
     * @notice See {IIPCollector.recoverIAVSigner}
     */
    function recoverIAVSigner(SignedIAV calldata _signedIAV) external view returns (address) {
        return _recoverIAVSigner(_signedIAV);
    }

    function _recoverIAVSigner(SignedIAV memory _signedIAV) private view returns (address) {
        bytes32 messageHash = _encodeIAV(_signedIAV.iav);
        return ECDSA.recover(messageHash, _signedIAV.signature);
    }

    /**
     * @notice See {IIPCollector.encodeIAV}
     */
    function encodeIAV(IndexingAgreementVoucher calldata _iav) external view returns (bytes32) {
        return _encodeIAV(_iav);
    }

    function _encodeIAV(IndexingAgreementVoucher memory _iav) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(EIP712_IAV_TYPEHASH, _iav.dataService, _iav.serviceProvider, keccak256(_iav.metadata))
                )
            );
    }
}

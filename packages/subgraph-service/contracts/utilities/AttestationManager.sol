// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { AttestationManagerV1Storage } from "./AttestationManagerStorage.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import { Attestation } from "../libraries/Attestation.sol";

/**
 * @title AttestationManager contract
 * @notice A helper contract implementing EIP712 attestation verification.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract AttestationManager is EIP712Upgradeable, AttestationManagerV1Storage {
    ///@dev EIP712 typehash for allocation id proof
    bytes32 private constant EIP712_RECEIPT_TYPEHASH =
        keccak256("Receipt(bytes32 requestHash,bytes32 responseHash,bytes32 subgraphDeploymentID)");

    /**
     * @dev Initialize the AttestationManager contract and parent contracts
     */
    // solhint-disable-next-line func-name-mixedcase
    function __AttestationManager_init(string memory _name, string memory _version) internal onlyInitializing {
        __EIP712_init(_name, _version);
        __AttestationManager_init_unchained();
    }

    /**
     * @dev Initialize the AttestationManager contract
     */
    // solhint-disable-next-line func-name-mixedcase
    function __AttestationManager_init_unchained() internal onlyInitializing {}

    /**
     * @dev Recover the signer address of the `_attestation`.
     * @param _attestation The attestation struct
     * @return Signer address
     */
    function _recoverSigner(Attestation.State memory _attestation) internal view returns (address) {
        // Obtain the hash of the fully-encoded message, per EIP-712 encoding
        Attestation.Receipt memory receipt = Attestation.Receipt(
            _attestation.requestHash,
            _attestation.responseHash,
            _attestation.subgraphDeploymentId
        );
        bytes32 messageHash = _encodeReceipt(receipt);

        // Obtain the signer of the fully-encoded EIP-712 message hash
        // NOTE: The signer of the attestation is the indexer that served the request
        return ECDSA.recover(messageHash, _attestation.signature);
    }

    /**
     * @dev Encodes the attestation receipt for EIP712 signing
     * @param _receipt Receipt returned by indexer and submitted by fisherman
     * @return Encoded receipt
     */
    function _encodeReceipt(Attestation.Receipt memory _receipt) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EIP712_RECEIPT_TYPEHASH,
                        _receipt.requestHash,
                        _receipt.responseHash,
                        _receipt.subgraphDeploymentId
                    )
                )
            );
    }
}

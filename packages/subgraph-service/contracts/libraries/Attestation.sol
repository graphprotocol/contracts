// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-strict-inequalities
// forge-lint: disable-start(mixed-case-variable)

import { IAttestation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAttestation.sol";

/**
 * @title Attestation library
 * @author Edge & Node
 * @notice A library to handle Attestation
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library Attestation {
    /// @notice Attestation size is the sum of the receipt (96) + signature (65)
    uint256 private constant RECEIPT_SIZE_BYTES = 96;

    /// @notice The length of the r value of the signature
    uint256 private constant SIG_R_LENGTH = 32;

    /// @notice The length of the s value of the signature
    uint256 private constant SIG_S_LENGTH = 32;

    /// @notice The length of the v value of the signature
    uint256 private constant SIG_V_LENGTH = 1;

    /// @notice The offset of the r value of the signature
    uint256 private constant SIG_R_OFFSET = RECEIPT_SIZE_BYTES;

    /// @notice The offset of the s value of the signature
    uint256 private constant SIG_S_OFFSET = RECEIPT_SIZE_BYTES + SIG_R_LENGTH;

    /// @notice The offset of the v value of the signature
    uint256 private constant SIG_V_OFFSET = RECEIPT_SIZE_BYTES + SIG_R_LENGTH + SIG_S_LENGTH;

    /// @notice The size of the signature
    uint256 private constant SIG_SIZE_BYTES = SIG_R_LENGTH + SIG_S_LENGTH + SIG_V_LENGTH;

    /// @notice The size of the attestation
    uint256 private constant ATTESTATION_SIZE_BYTES = RECEIPT_SIZE_BYTES + SIG_SIZE_BYTES;

    /// @notice The length of the uint8 value
    uint256 private constant UINT8_BYTE_LENGTH = 1;

    /// @notice The length of the bytes32 value
    uint256 private constant BYTES32_BYTE_LENGTH = 32;

    /**
     * @notice Returns if two attestations are conflicting
     * @dev Everything must match except for the responseId
     * @param _attestation1 Attestation
     * @param _attestation2 Attestation
     * @return True if the two attestations are conflicting
     */
    function areConflicting(
        IAttestation.State memory _attestation1,
        IAttestation.State memory _attestation2
    ) internal pure returns (bool) {
        return (_attestation1.requestCID == _attestation2.requestCID &&
            _attestation1.subgraphDeploymentId == _attestation2.subgraphDeploymentId &&
            _attestation1.responseCID != _attestation2.responseCID);
    }

    /**
     * @notice Parse the bytes attestation into a struct from `_data`
     * @param _data The bytes to parse
     * @return Attestation struct
     */
    function parse(bytes memory _data) internal pure returns (IAttestation.State memory) {
        // Check attestation data length
        require(
            _data.length == ATTESTATION_SIZE_BYTES,
            IAttestation.AttestationInvalidBytesLength(_data.length, ATTESTATION_SIZE_BYTES)
        );

        // Decode receipt
        (bytes32 requestCID, bytes32 responseCID, bytes32 subgraphDeploymentId) = abi.decode(
            _data,
            (bytes32, bytes32, bytes32)
        );

        // Decode signature
        // Signature is expected to be in the order defined in the Attestation struct
        bytes32 r = _toBytes32(_data, SIG_R_OFFSET);
        bytes32 s = _toBytes32(_data, SIG_S_OFFSET);
        uint8 v = _toUint8(_data, SIG_V_OFFSET);

        return IAttestation.State(requestCID, responseCID, subgraphDeploymentId, r, s, v);
    }

    /**
     * @notice Parse a uint8 from `_bytes` starting at offset `_start`
     * @param _bytes The bytes to parse
     * @param _start The start offset
     * @return uint8 value
     */
    function _toUint8(bytes memory _bytes, uint256 _start) private pure returns (uint8) {
        require(
            _bytes.length >= _start + UINT8_BYTE_LENGTH,
            IAttestation.AttestationInvalidBytesLength(_bytes.length, _start + UINT8_BYTE_LENGTH)
        );
        uint8 tempUint;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Load the 32-byte word from memory starting at `_bytes + _start + 1`
            // The `0x1` accounts for the fact that we want only the first byte (uint8)
            // of the loaded 32 bytes.
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    /**
     * @notice Parse a bytes32 from `_bytes` starting at offset `_start`
     * @param _bytes The bytes to parse
     * @param _start The start offset
     * @return bytes32 value
     */
    function _toBytes32(bytes memory _bytes, uint256 _start) private pure returns (bytes32) {
        require(
            _bytes.length >= _start + BYTES32_BYTE_LENGTH,
            IAttestation.AttestationInvalidBytesLength(_bytes.length, _start + BYTES32_BYTE_LENGTH)
        );
        bytes32 tempBytes32;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }
}

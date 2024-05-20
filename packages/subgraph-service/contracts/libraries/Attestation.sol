// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

library Attestation {
    // Receipt content sent from the service provider in response to request
    struct Receipt {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentId;
    }

    // Attestation sent from the service provider in response to a request
    struct State {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentId;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    // Attestation size is the sum of the receipt (96) + signature (65)
    uint256 private constant ATTESTATION_SIZE_BYTES = RECEIPT_SIZE_BYTES + SIG_SIZE_BYTES;
    uint256 private constant RECEIPT_SIZE_BYTES = 96;

    uint256 private constant SIG_R_LENGTH = 32;
    uint256 private constant SIG_S_LENGTH = 32;
    uint256 private constant SIG_V_LENGTH = 1;
    uint256 private constant SIG_R_OFFSET = RECEIPT_SIZE_BYTES;
    uint256 private constant SIG_S_OFFSET = RECEIPT_SIZE_BYTES + SIG_R_LENGTH;
    uint256 private constant SIG_V_OFFSET = RECEIPT_SIZE_BYTES + SIG_R_LENGTH + SIG_S_LENGTH;
    uint256 private constant SIG_SIZE_BYTES = SIG_R_LENGTH + SIG_S_LENGTH + SIG_V_LENGTH;

    uint256 private constant UINT8_BYTE_LENGTH = 1;
    uint256 private constant BYTES32_BYTE_LENGTH = 32;

    error AttestationInvalidBytesLength(uint256 length, uint256 expectedLength);

    /**
     * @dev Returns if two attestations are conflicting.
     * Everything must match except for the responseId.
     * @param _attestation1 Attestation
     * @param _attestation2 Attestation
     * @return True if the two attestations are conflicting
     */
    function areConflicting(
        Attestation.State memory _attestation1,
        Attestation.State memory _attestation2
    ) internal pure returns (bool) {
        return (_attestation1.requestCID == _attestation2.requestCID &&
            _attestation1.subgraphDeploymentId == _attestation2.subgraphDeploymentId &&
            _attestation1.responseCID != _attestation2.responseCID);
    }

    /**
     * @dev Parse the bytes attestation into a struct from `_data`.
     * @return Attestation struct
     */
    function parse(bytes memory _data) internal pure returns (State memory) {
        // Check attestation data length
        if (_data.length != ATTESTATION_SIZE_BYTES) {
            revert AttestationInvalidBytesLength(_data.length, ATTESTATION_SIZE_BYTES);
        }

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

        return State(requestCID, responseCID, subgraphDeploymentId, r, s, v);
    }

    /**
     * @dev Parse a uint8 from `_bytes` starting at offset `_start`.
     * @return uint8 value
     */
    function _toUint8(bytes memory _bytes, uint256 _start) private pure returns (uint8) {
        if (_bytes.length < (_start + UINT8_BYTE_LENGTH)) {
            revert AttestationInvalidBytesLength(_bytes.length, _start + UINT8_BYTE_LENGTH);
        }
        uint8 tempUint;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    /**
     * @dev Parse a bytes32 from `_bytes` starting at offset `_start`.
     * @return bytes32 value
     */
    function _toBytes32(bytes memory _bytes, uint256 _start) private pure returns (bytes32) {
        if (_bytes.length < (_start + BYTES32_BYTE_LENGTH)) {
            revert AttestationInvalidBytesLength(_bytes.length, _start + BYTES32_BYTE_LENGTH);
        }
        bytes32 tempBytes32;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }
}

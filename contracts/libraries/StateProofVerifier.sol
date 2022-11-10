// SPDX-License-Identifier: MIT

/*
 * Copied from:
 * https://github.com/lidofinance/curve-merkle-oracle/blob/1033b3e84142317ffd8f366b52e489d5eb49c73f/contracts/StateProofVerifier.sol
 *
 * MODIFIED from lidofinance's implementation:
 * - Changed solidity version to 0.7.6 (pablo@edgeandnode.com)
 * - Using local copy of the RLPReader library instead of using the package
 * - Explicitly marked visibility of constants
 * - Added revert messages
 * - A few other QA improvements, e.g. NatSpec
 */

pragma solidity 0.7.6;

import { RLPReader } from "./RLPReader.sol";
import { MerklePatriciaProofVerifier } from "./MerklePatriciaProofVerifier.sol";

/**
 * @title A helper library for verification of Merkle Patricia account and state proofs.
 */
library StateProofVerifier {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    /// Index within a block header for the state root hash
    uint256 public constant HEADER_STATE_ROOT_INDEX = 3;
    /// Index within a block header for the block number
    uint256 public constant HEADER_NUMBER_INDEX = 8;
    /// Index within a block header for the timestamp
    uint256 public constant HEADER_TIMESTAMP_INDEX = 11;

    struct BlockHeader {
        bytes32 hash;
        bytes32 stateRootHash;
        uint256 number;
        uint256 timestamp;
    }

    struct Account {
        bool exists;
        uint256 nonce;
        uint256 balance;
        bytes32 storageRoot;
        bytes32 codeHash;
    }

    struct SlotValue {
        bool exists;
        uint256 value;
    }

    /**
     * @notice Parses block header and verifies its presence onchain within the latest 256 blocks.
     * @param _headerRlpBytes RLP-encoded block header.
     * @return The block header as a BlockHeader struct.
     */
    function verifyBlockHeader(bytes memory _headerRlpBytes)
        internal
        view
        returns (BlockHeader memory)
    {
        BlockHeader memory header = parseBlockHeader(_headerRlpBytes);
        // ensure that the block is actually in the blockchain
        require(header.hash == blockhash(header.number), "SPV: blockhash mismatch");
        return header;
    }

    /**
     * @notice Parses RLP-encoded block header.
     * @param _headerRlpBytes RLP-encoded block header.
     * @return The block header as a BlockHeader struct.
     */
    function parseBlockHeader(bytes memory _headerRlpBytes)
        internal
        pure
        returns (BlockHeader memory)
    {
        BlockHeader memory result;
        RLPReader.RLPItem[] memory headerFields = _headerRlpBytes.toRlpItem().toList();

        require(headerFields.length > HEADER_TIMESTAMP_INDEX, "SPV: invalid header length");

        result.stateRootHash = bytes32(headerFields[HEADER_STATE_ROOT_INDEX].toUint());
        result.number = headerFields[HEADER_NUMBER_INDEX].toUint();
        result.timestamp = headerFields[HEADER_TIMESTAMP_INDEX].toUint();
        result.hash = keccak256(_headerRlpBytes);

        return result;
    }

    /**
     * @dev Verifies Merkle Patricia proof of an account and extracts the account fields.
     * @param _addressHash Keccak256 hash of the address corresponding to the account.
     * @param _stateRootHash MPT root hash of the Ethereum state trie.
     * @param _proof RLP-encoded Merkle Patricia proof for the account.
     * @return The account as an Account struct, if the proof shows it exists, or an empty struct otherwise.
     */
    function extractAccountFromProof(
        bytes32 _addressHash, // keccak256(abi.encodePacked(address))
        bytes32 _stateRootHash,
        RLPReader.RLPItem[] memory _proof
    ) internal pure returns (Account memory) {
        bytes memory acctRlpBytes = MerklePatriciaProofVerifier.extractProofValue(
            _stateRootHash,
            abi.encodePacked(_addressHash),
            _proof
        );

        Account memory account;

        if (acctRlpBytes.length == 0) {
            return account;
        }

        RLPReader.RLPItem[] memory acctFields = acctRlpBytes.toRlpItem().toList();
        require(acctFields.length == 4, "SPV: invalid accFields length");

        account.exists = true;
        account.nonce = acctFields[0].toUint();
        account.balance = acctFields[1].toUint();
        account.storageRoot = bytes32(acctFields[2].toUint());
        account.codeHash = bytes32(acctFields[3].toUint());

        return account;
    }

    /**
     * @dev Verifies Merkle Patricia proof of a slot and extracts the slot's value.
     * @param _slotHash Keccak256 hash of the slot position.
     * @param _storageRootHash MPT root hash of the account's storage trie.
     * @param _proof RLP-encoded Merkle Patricia proof for the slot.
     * @return The slot's value as a SlotValue struct, if the proof shows it exists, or an empty struct otherwise.
     */
    function extractSlotValueFromProof(
        bytes32 _slotHash,
        bytes32 _storageRootHash,
        RLPReader.RLPItem[] memory _proof
    ) internal pure returns (SlotValue memory) {
        bytes memory valueRlpBytes = MerklePatriciaProofVerifier.extractProofValue(
            _storageRootHash,
            abi.encodePacked(_slotHash),
            _proof
        );

        SlotValue memory value;

        if (valueRlpBytes.length != 0) {
            value.exists = true;
            value.value = valueRlpBytes.toRlpItem().toUint();
        }

        return value;
    }
}

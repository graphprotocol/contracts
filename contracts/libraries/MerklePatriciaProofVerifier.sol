// SPDX-License-Identifier: MIT

/*
 * Copied from:
 * https://github.com/lidofinance/curve-merkle-oracle/blob/1033b3e84142317ffd8f366b52e489d5eb49c73f/contracts/MerklePatriciaProofVerifier.sol
 *
 * MODIFIED from lidofinance's implementation:
 * - Changed solidity version to 0.7.6 (pablo@edgeandnode.com)
 * - Using local copy of the RLPReader library instead of using the package
 * - Silenced linter warnings about inline assembly
 * - Renamed a variable for mixedCase consistency
 * - Added clearer revert messages
 * - Use assert when checking for a condition that should be impossible (nibble >= 16)
 * - Other minor QA changes
 */

/**
 * Copied from https://github.com/lorenzb/proveth/blob/c74b20e/onchain/ProvethVerifier.sol
 * with minor performance and code style-related modifications.
 */
pragma solidity 0.7.6;

import { RLPReader } from "./RLPReader.sol";

/**
 * @title MerklePatriciaProofVerifier
 * @notice This contract verifies proofs of inclusion or exclusion
 * for Merkle Patricia tries.
 */
library MerklePatriciaProofVerifier {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    /// @dev Validates a Merkle-Patricia-Trie proof.
    ///      If the proof proves the inclusion of some key-value pair in the
    ///      trie, the value is returned. Otherwise, i.e. if the proof proves
    ///      the exclusion of a key from the trie, an empty byte array is
    ///      returned.
    /// @param rootHash is the Keccak-256 hash of the root node of the MPT.
    /// @param path is the key of the node whose inclusion/exclusion we are
    ///        proving.
    /// @param stack is the stack of MPT nodes (starting with the root) that
    ///        need to be traversed during verification.
    /// @return value whose inclusion is proved or an empty byte array for
    ///         a proof of exclusion
    function extractProofValue(
        bytes32 rootHash,
        bytes memory path,
        RLPReader.RLPItem[] memory stack
    ) internal pure returns (bytes memory value) {
        bytes memory mptKey = _decodeNibbles(path, 0);
        uint256 mptKeyOffset;

        bytes32 nodeHashHash;
        RLPReader.RLPItem[] memory node;

        RLPReader.RLPItem memory rlpValue;

        if (stack.length == 0) {
            // Root hash of empty Merkle-Patricia-Trie
            require(
                rootHash == 0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421,
                "MPT: invalid empty tree root"
            );
            return new bytes(0);
        }

        // Traverse stack of nodes starting at root.
        for (uint256 i; i < stack.length; ++i) {
            // We use the fact that an rlp encoded list consists of some
            // encoding of its length plus the concatenation of its
            // *rlp-encoded* items.

            // The root node is hashed with Keccak-256 ...
            if (i == 0 && rootHash != stack[i].rlpBytesKeccak256()) {
                revert("MPT: invalid root hash");
            }
            // ... whereas all other nodes are hashed with the MPT
            // hash function.
            if (i != 0 && nodeHashHash != _mptHashHash(stack[i])) {
                revert("MPT: invalid node hash");
            }
            // We verified that stack[i] has the correct hash, so we
            // may safely decode it.
            node = stack[i].toList();

            if (node.length == 2) {
                // Extension or Leaf node

                bool isLeaf;
                bytes memory nodeKey;
                (isLeaf, nodeKey) = _merklePatriciaCompactDecode(node[0].toBytes());

                uint256 prefixLength = _sharedPrefixLength(mptKeyOffset, mptKey, nodeKey);
                mptKeyOffset += prefixLength;

                if (prefixLength < nodeKey.length) {
                    // Proof claims divergent extension or leaf. (Only
                    // relevant for proofs of exclusion.)
                    // An Extension/Leaf node is divergent iff it "skips" over
                    // the point at which a Branch node should have been had the
                    // excluded key been included in the trie.
                    // Example: Imagine a proof of exclusion for path [1, 4],
                    // where the current node is a Leaf node with
                    // path [1, 3, 3, 7]. For [1, 4] to be included, there
                    // should have been a Branch node at [1] with a child
                    // at 3 and a child at 4.

                    // Sanity check
                    if (i < stack.length - 1) {
                        // divergent node must come last in proof
                        revert("MPT: divergent node not last");
                    }

                    return new bytes(0);
                }

                if (isLeaf) {
                    // Sanity check
                    if (i < stack.length - 1) {
                        // leaf node must come last in proof
                        revert("MPT: leaf node not last");
                    }

                    if (mptKeyOffset < mptKey.length) {
                        return new bytes(0);
                    }

                    rlpValue = node[1];
                    return rlpValue.toBytes();
                } else {
                    // extension
                    // Sanity check
                    if (i == stack.length - 1) {
                        // shouldn't be at last level
                        revert("MPT: non-leaf node last");
                    }

                    if (!node[1].isList()) {
                        // rlp(child) was at least 32 bytes. node[1] contains
                        // Keccak256(rlp(child)).
                        nodeHashHash = node[1].payloadKeccak256();
                    } else {
                        // rlp(child) was less than 32 bytes. node[1] contains
                        // rlp(child).
                        nodeHashHash = node[1].rlpBytesKeccak256();
                    }
                }
            } else if (node.length == 17) {
                // Branch node

                if (mptKeyOffset != mptKey.length) {
                    // we haven't consumed the entire path, so we need to look at a child
                    uint8 nibble = uint8(mptKey[mptKeyOffset]);
                    mptKeyOffset += 1;

                    // mptKey comes from _decodeNibbles which should never
                    // return a nibble >= 16, which is why we should never
                    // ever have a nibble >= 16 here. (This is a sanity check
                    // which is why we use assert and not require.)
                    assert(nibble < 16);

                    if (_isEmptyByteSequence(node[nibble])) {
                        // Sanity
                        if (i != stack.length - 1) {
                            // leaf node should be at last level
                            revert("MPT: empty leaf not last");
                        }

                        return new bytes(0);
                    } else if (!node[nibble].isList()) {
                        nodeHashHash = node[nibble].payloadKeccak256();
                    } else {
                        nodeHashHash = node[nibble].rlpBytesKeccak256();
                    }
                } else {
                    // we have consumed the entire mptKey, so we need to look at what's contained in this node.

                    // Sanity
                    if (i != stack.length - 1) {
                        // should be at last level
                        revert("MPT: end not last");
                    }

                    return node[16].toBytes();
                }
            }
        }
    }

    /// @dev Computes the hash of the Merkle-Patricia-Trie hash of the RLP item.
    ///      Merkle-Patricia-Tries use a weird "hash function" that outputs
    ///      *variable-length* hashes: If the item is shorter than 32 bytes,
    ///      the MPT hash is the item. Otherwise, the MPT hash is the
    ///      Keccak-256 hash of the item.
    ///      The easiest way to compare variable-length byte sequences is
    ///      to compare their Keccak-256 hashes.
    /// @param item The RLP item to be hashed.
    /// @return Keccak-256(MPT-hash(item))
    function _mptHashHash(RLPReader.RLPItem memory item) private pure returns (bytes32) {
        if (item.len < 32) {
            return item.rlpBytesKeccak256();
        } else {
            return keccak256(abi.encodePacked(item.rlpBytesKeccak256()));
        }
    }

    /**
     * @dev Checks if an RLP item corresponds to an empty byte sequence, encoded as 0x80.
     * @param item The RLP item to be checked.
     * @return True if the item is an empty byte string, false otherwise.
     */
    function _isEmptyByteSequence(RLPReader.RLPItem memory item) private pure returns (bool) {
        if (item.len != 1) {
            return false;
        }
        uint8 b;
        uint256 memPtr = item.memPtr;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            b := byte(0, mload(memPtr))
        }
        return b == 0x80; /* empty byte string */
    }

    /**
     * @dev Decode a compact-encoded Merkle-Patricia proof node,
     * which must be a leaf or extension node
     * @param compact The compact-encoded node
     * @return isLeaf True if the node is a leaf node, false if it is an extension node.
     * @return nibbles The decoded path of the node split into nibbles.
     */
    function _merklePatriciaCompactDecode(bytes memory compact)
        private
        pure
        returns (bool isLeaf, bytes memory nibbles)
    {
        require(compact.length > 0, "MPT: invalid compact length");
        uint256 firstNibble = (uint8(compact[0]) >> 4) & 0xF;
        uint256 skipNibbles;
        if (firstNibble == 0) {
            skipNibbles = 2;
            isLeaf = false;
        } else if (firstNibble == 1) {
            skipNibbles = 1;
            isLeaf = false;
        } else if (firstNibble == 2) {
            skipNibbles = 2;
            isLeaf = true;
        } else if (firstNibble == 3) {
            skipNibbles = 1;
            isLeaf = true;
        } else {
            // Not supposed to happen!
            revert("MPT: invalid first nibble");
        }
        return (isLeaf, _decodeNibbles(compact, skipNibbles));
    }

    /**
     * @dev Decode the nibbles of a compact-encoded Merkle-Patricia proof node.
     * @param compact The compact-encoded node
     * @param skipNibbles The number of nibbles to skip at the beginning of the node.
     * @return nibbles The decoded path of the node split into nibbles.
     */
    function _decodeNibbles(bytes memory compact, uint256 skipNibbles)
        private
        pure
        returns (bytes memory nibbles)
    {
        require(compact.length != 0, "MPT: _dN invalid compact length");

        uint256 length = compact.length * 2;
        require(skipNibbles <= length, "MPT: _dN invalid skipNibbles");
        length -= skipNibbles;

        nibbles = new bytes(length);
        uint256 nibblesLength;

        for (uint256 i = skipNibbles; i < skipNibbles + length; i += 1) {
            if (i % 2 == 0) {
                nibbles[nibblesLength] = bytes1((uint8(compact[i / 2]) >> 4) & 0xF);
            } else {
                nibbles[nibblesLength] = bytes1((uint8(compact[i / 2])) & 0xF);
            }
            nibblesLength += 1;
        }

        assert(nibblesLength == nibbles.length);
    }

    /**
     * @dev Compute the length of the shared prefix between two byte sequences.
     * This will be the count of how many bytes (representing path nibbles) are the same at the beginning of the sequences.
     * @param xsOffset The offset to skip on the first sequence
     * @param xs The first sequence
     * @param ys The second sequence
     * @return The length of the shared prefix.
     */
    function _sharedPrefixLength(
        uint256 xsOffset,
        bytes memory xs,
        bytes memory ys
    ) private pure returns (uint256) {
        uint256 i;
        for (; i + xsOffset < xs.length && i < ys.length; ++i) {
            if (xs[i + xsOffset] != ys[i]) {
                return i;
            }
        }
        return i;
    }
}

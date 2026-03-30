// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { RecurringCollectorSharedTest } from "./shared.t.sol";

function contentHashTerms(IRecurringCollector.AgreementTerms memory terms) pure returns (bytes32) {
    return
        keccak256(
            abi.encode(
                terms.deadline,
                terms.endsAt,
                terms.maxInitialTokens,
                terms.maxOngoingTokensPerSecond,
                terms.minSecondsPerCollection,
                terms.maxSecondsPerCollection,
                terms.conditions,
                terms.minSecondsPayerCancellationNotice,
                keccak256(terms.metadata)
            )
        );
}

/// @notice Tests for hashing functions (hashRCA, hashRCAU, contentHashTerms)
contract RecurringCollectorHashingTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_ContentHashTerms_DeterministicForSameInput() public view {
        IRecurringCollector.AgreementTerms memory terms = IRecurringCollector.AgreementTerms({
            deadline: 1000,
            endsAt: 2000,
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 60,
            maxSecondsPerCollection: 3600,
            conditions: 0,
            minSecondsPayerCancellationNotice: 0,
            hash: bytes32(0),
            metadata: "test"
        });

        bytes32 hash1 = contentHashTerms(terms);
        bytes32 hash2 = contentHashTerms(terms);
        assertEq(hash1, hash2, "Same input should produce same hash");
        assertTrue(hash1 != bytes32(0), "Hash should not be zero");
    }

    function _makeTerms(
        uint256 rate,
        bytes memory metadata
    ) private pure returns (IRecurringCollector.AgreementTerms memory) {
        return
            IRecurringCollector.AgreementTerms({
                deadline: 1000,
                endsAt: 2000,
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: rate,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 0,
                hash: bytes32(0),
                metadata: metadata
            });
    }

    function test_ContentHashTerms_DiffersWhenFieldChanges() public view {
        bytes32 hash1 = contentHashTerms(_makeTerms(1 ether, "test"));
        bytes32 hash2 = contentHashTerms(_makeTerms(2 ether, "test"));
        assertTrue(hash1 != hash2, "Different terms should produce different hashes");
    }

    function test_ContentHashTerms_DiffersWhenMetadataChanges() public view {
        bytes32 hash1 = contentHashTerms(_makeTerms(1 ether, "metadata-A"));
        bytes32 hash2 = contentHashTerms(_makeTerms(1 ether, "metadata-B"));
        assertTrue(hash1 != hash2, "Different metadata should produce different hashes");
    }

    function test_ContentHashTerms_IgnoresHashField() public view {
        IRecurringCollector.AgreementTerms memory termsA = _makeTerms(1 ether, "test");
        termsA.hash = bytes32(uint256(1));
        IRecurringCollector.AgreementTerms memory termsB = _makeTerms(1 ether, "test");
        termsB.hash = bytes32(uint256(999));

        bytes32 hash1 = contentHashTerms(termsA);
        bytes32 hash2 = contentHashTerms(termsB);
        assertEq(hash1, hash2, "Hash field itself should not affect contentHash");
    }

    /* solhint-enable graph/func-name-mixedcase */
}

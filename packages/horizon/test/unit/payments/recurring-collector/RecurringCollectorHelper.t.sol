// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "../../../../contracts/interfaces/IRecurringCollector.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";
import { AuthorizableHelper } from "../../../unit/utilities/Authorizable.t.sol";
import { Bounder } from "../../../unit/utils/Bounder.t.sol";

contract RecurringCollectorHelper is AuthorizableHelper, Bounder {
    RecurringCollector public collector;

    constructor(
        RecurringCollector collector_
    ) AuthorizableHelper(collector_, collector_.REVOKE_AUTHORIZATION_THAWING_PERIOD()) {
        collector = collector_;
    }

    function generateSignedRCA(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 signerPrivateKey
    ) public view returns (IRecurringCollector.SignedRCA memory) {
        bytes32 messageHash = collector.hashRCA(rca);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IRecurringCollector.SignedRCA memory signedRCA = IRecurringCollector.SignedRCA({
            rca: rca,
            signature: signature
        });

        return signedRCA;
    }

    function generateSignedRCAU(
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau,
        uint256 signerPrivateKey
    ) public view returns (IRecurringCollector.SignedRCAU memory) {
        bytes32 messageHash = collector.hashRCAU(rcau);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IRecurringCollector.SignedRCAU memory signedRCAU = IRecurringCollector.SignedRCAU({
            rcau: rcau,
            signature: signature
        });

        return signedRCAU;
    }

    function generateSignedRCAUWithCorrectNonce(
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau,
        uint256 signerPrivateKey
    ) public view returns (IRecurringCollector.SignedRCAU memory) {
        // Automatically set the correct nonce based on current agreement state
        IRecurringCollector.AgreementData memory agreement = collector.getAgreement(rcau.agreementId);
        rcau.nonce = agreement.updateNonce + 1;

        return generateSignedRCAU(rcau, signerPrivateKey);
    }

    function withElapsedAcceptDeadline(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) public view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        require(block.timestamp > 0, "block.timestamp can't be zero");
        require(block.timestamp <= type(uint64).max, "block.timestamp can't be huge");
        rca.deadline = uint64(bound(rca.deadline, 0, block.timestamp - 1));
        return rca;
    }

    function withOKAcceptDeadline(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) public view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        require(block.timestamp <= type(uint64).max, "block.timestamp can't be huge");
        rca.deadline = uint64(boundTimestampMin(rca.deadline, block.timestamp));
        return rca;
    }

    function sensibleRCA(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) public view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        vm.assume(rca.agreementId != bytes16(0));
        vm.assume(rca.dataService != address(0));
        vm.assume(rca.payer != address(0));
        vm.assume(rca.serviceProvider != address(0));

        rca.minSecondsPerCollection = _sensibleMinSecondsPerCollection(rca.minSecondsPerCollection);
        rca.maxSecondsPerCollection = _sensibleMaxSecondsPerCollection(
            rca.maxSecondsPerCollection,
            rca.minSecondsPerCollection
        );

        rca.deadline = _sensibleDeadline(rca.deadline);
        rca.endsAt = _sensibleEndsAt(rca.endsAt, rca.maxSecondsPerCollection);

        rca.maxInitialTokens = _sensibleMaxInitialTokens(rca.maxInitialTokens);
        rca.maxOngoingTokensPerSecond = _sensibleMaxOngoingTokensPerSecond(rca.maxOngoingTokensPerSecond);

        return rca;
    }

    function sensibleRCAU(
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau
    ) public view returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        rcau.minSecondsPerCollection = _sensibleMinSecondsPerCollection(rcau.minSecondsPerCollection);
        rcau.maxSecondsPerCollection = _sensibleMaxSecondsPerCollection(
            rcau.maxSecondsPerCollection,
            rcau.minSecondsPerCollection
        );

        rcau.deadline = _sensibleDeadline(rcau.deadline);
        rcau.endsAt = _sensibleEndsAt(rcau.endsAt, rcau.maxSecondsPerCollection);
        rcau.maxInitialTokens = _sensibleMaxInitialTokens(rcau.maxInitialTokens);
        rcau.maxOngoingTokensPerSecond = _sensibleMaxOngoingTokensPerSecond(rcau.maxOngoingTokensPerSecond);

        return rcau;
    }

    function _sensibleDeadline(uint256 _seed) internal view returns (uint64) {
        return
            uint64(
                bound(_seed, block.timestamp + 1, block.timestamp + uint256(collector.MIN_SECONDS_COLLECTION_WINDOW()))
            ); // between now and +MIN_SECONDS_COLLECTION_WINDOW
    }

    function _sensibleEndsAt(uint256 _seed, uint32 _maxSecondsPerCollection) internal view returns (uint64) {
        return
            uint64(
                bound(
                    _seed,
                    block.timestamp + (10 * uint256(_maxSecondsPerCollection)),
                    block.timestamp + (1_000_000 * uint256(_maxSecondsPerCollection))
                )
            ); // between 10 and 1M max collections
    }

    function _sensibleMaxSecondsPerCollection(
        uint32 _seed,
        uint32 _minSecondsPerCollection
    ) internal view returns (uint32) {
        return
            uint32(
                bound(
                    _seed,
                    _minSecondsPerCollection + uint256(collector.MIN_SECONDS_COLLECTION_WINDOW()),
                    60 * 60 * 24 * 30
                ) // between minSecondsPerCollection + 2h and 30 days
            );
    }

    function _sensibleMaxInitialTokens(uint256 _seed) internal pure returns (uint256) {
        return bound(_seed, 0, 1e18 * 100_000_000); // between 0 and 100M tokens
    }

    function _sensibleMaxOngoingTokensPerSecond(uint256 _seed) internal pure returns (uint256) {
        return bound(_seed, 1, 1e18); // between 1 and 1e18 tokens per second
    }

    function _sensibleMinSecondsPerCollection(uint32 _seed) internal pure returns (uint32) {
        return uint32(bound(_seed, 10 * 60, 24 * 60 * 60)); // between 10 min and 24h
    }
}

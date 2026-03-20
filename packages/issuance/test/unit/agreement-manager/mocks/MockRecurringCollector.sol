// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

/// @notice Minimal mock of RecurringCollector for RecurringAgreementManager testing.
/// Stores agreement data set by tests, computes agreementId and hashRCA deterministically.
contract MockRecurringCollector {
    mapping(bytes16 => IRecurringCollector.AgreementData) private _agreements;
    mapping(bytes16 => bool) private _agreementExists;

    // -- Test helpers --

    function setAgreement(bytes16 agreementId, IRecurringCollector.AgreementData memory data) external {
        _agreements[agreementId] = data;
        _agreementExists[agreementId] = true;
    }

    // -- IRecurringCollector subset --

    function getAgreement(bytes16 agreementId) external view returns (IRecurringCollector.AgreementData memory) {
        return _agreements[agreementId];
    }

    function getMaxNextClaim(bytes16 agreementId) external view returns (uint256) {
        return _mockGetMaxNextClaim(_agreements[agreementId]);
    }

    function _mockGetMaxNextClaim(IRecurringCollector.AgreementData memory a) private pure returns (uint256) {
        if (a.state == IRecurringCollector.AgreementState.CanceledByServiceProvider) return 0;
        if (
            a.state != IRecurringCollector.AgreementState.Accepted &&
            a.state != IRecurringCollector.AgreementState.CanceledByPayer
        ) return 0;

        uint256 collectionStart = 0 < a.lastCollectionAt ? a.lastCollectionAt : a.acceptedAt;
        uint256 collectionEnd;
        if (a.state == IRecurringCollector.AgreementState.CanceledByPayer) {
            collectionEnd = a.canceledAt < a.endsAt ? a.canceledAt : a.endsAt;
        } else {
            collectionEnd = a.endsAt;
        }
        if (collectionEnd <= collectionStart) return 0;

        uint256 windowSeconds = collectionEnd - collectionStart;
        uint256 maxSeconds = windowSeconds < a.maxSecondsPerCollection ? windowSeconds : a.maxSecondsPerCollection;
        uint256 maxClaim = a.maxOngoingTokensPerSecond * maxSeconds;
        if (a.lastCollectionAt == 0) maxClaim += a.maxInitialTokens;
        return maxClaim;
    }

    function computeMaxFirstClaim(
        IRecurringCollector.RecurringCollectionAgreement calldata rca
    ) external view returns (uint256) {
        return
            _computeMaxClaim(
                rca.maxOngoingTokensPerSecond,
                rca.maxSecondsPerCollection,
                rca.maxInitialTokens,
                rca.endsAt
            );
    }

    function computeMaxUpdateClaim(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau
    ) external view returns (uint256 initialExtra, uint256 ongoing) {
        ongoing = _computeMaxClaim(rcau.maxOngoingTokensPerSecond, rcau.maxSecondsPerCollection, 0, rcau.endsAt);
        initialExtra = _agreements[agreementId].lastCollectionAt == 0 ? rcau.maxInitialTokens : 0;
    }

    function _computeMaxClaim(
        uint256 maxOngoingTokensPerSecond,
        uint256 maxSecondsPerCollection,
        uint256 maxInitialTokens,
        uint256 endsAt
    ) private view returns (uint256) {
        uint256 remainingSeconds = block.timestamp < endsAt ? endsAt - block.timestamp : 0;
        uint256 effectiveSeconds = remainingSeconds < maxSecondsPerCollection
            ? remainingSeconds
            : maxSecondsPerCollection;
        return maxOngoingTokensPerSecond * effectiveSeconds + maxInitialTokens;
    }

    function generateAgreementId(
        address payer,
        address dataService,
        address serviceProvider,
        uint64 deadline,
        uint256 nonce
    ) external pure returns (bytes16) {
        return bytes16(keccak256(abi.encode(payer, dataService, serviceProvider, deadline, nonce)));
    }

    function hashRCA(IRecurringCollector.RecurringCollectionAgreement calldata rca) external pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    rca.deadline,
                    rca.endsAt,
                    rca.payer,
                    rca.dataService,
                    rca.serviceProvider,
                    rca.maxInitialTokens,
                    rca.maxOngoingTokensPerSecond,
                    rca.minSecondsPerCollection,
                    rca.maxSecondsPerCollection,
                    rca.nonce,
                    rca.metadata
                )
            );
    }

    function hashRCAU(
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau
    ) external pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    rcau.agreementId,
                    rcau.deadline,
                    rcau.endsAt,
                    rcau.maxInitialTokens,
                    rcau.maxOngoingTokensPerSecond,
                    rcau.minSecondsPerCollection,
                    rcau.maxSecondsPerCollection,
                    rcau.nonce,
                    rcau.metadata
                )
            );
    }
}

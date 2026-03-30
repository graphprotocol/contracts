// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PAYER,
    BY_PROVIDER,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
/// @notice Minimal mock of RecurringCollector for RecurringAgreementManager testing.
/// Stores agreement data set by tests, computes agreementId and hashRCA deterministically.
contract MockRecurringCollector {
    /// @dev Internal storage layout for mock agreements. Mirrors the real RecurringCollector's
    /// internal AgreementStorage struct so tests can set up state with full fidelity.
    struct AgreementStorage {
        address dataService;
        uint64 acceptedAt;
        uint32 updateNonce;
        address payer;
        uint64 lastCollectionAt;
        uint16 state;
        address serviceProvider;
        uint64 collectableUntil;
        IRecurringCollector.AgreementTerms activeTerms;
        IRecurringCollector.AgreementTerms pendingTerms;
    }

    mapping(bytes16 => AgreementStorage) private _agreements;
    mapping(bytes16 => bool) private _agreementExists;

    // -- Test helpers --

    function setAgreement(bytes16 agreementId, AgreementStorage memory data) external {
        _agreements[agreementId] = data;
        _agreementExists[agreementId] = true;
    }

    // -- IRecurringCollector subset --

    function getAgreementData(bytes16 agreementId) external view returns (IRecurringCollector.AgreementData memory data_) {
        AgreementStorage storage a = _agreements[agreementId];
        data_.agreementId = agreementId;
        data_.payer = a.payer;
        data_.serviceProvider = a.serviceProvider;
        data_.dataService = a.dataService;
        data_.acceptedAt = a.acceptedAt;
        data_.lastCollectionAt = a.lastCollectionAt;
        data_.collectableUntil = a.collectableUntil;
        data_.updateNonce = a.updateNonce;
        data_.state = a.state;
        // Simplified collectability: accepted and not settled
        data_.isCollectable = (a.state & ACCEPTED) != 0 && (a.state & SETTLED) == 0;
        data_.collectionSeconds = 0; // Not needed for agreement manager tests
    }

    function getAgreementDetails(
        bytes16 agreementId,
        uint256 index
    ) external view returns (IAgreementCollector.AgreementDetails memory details) {
        AgreementStorage storage a = _agreements[agreementId];
        details.agreementId = agreementId;
        details.payer = a.payer;
        details.dataService = a.dataService;
        details.serviceProvider = a.serviceProvider;
        details.state = a.state;
        if (index == 0) {
            details.versionHash = a.activeTerms.hash;
        } else if (index == 1) {
            details.versionHash = a.pendingTerms.hash;
        }
    }

    function getMaxNextClaim(bytes16 agreementId) external view returns (uint256) {
        return this.getMaxNextClaim(agreementId, 3);
    }

    function getMaxNextClaim(bytes16 agreementId, uint8 claimScope) external view returns (uint256 maxClaim) {
        AgreementStorage storage a = _agreements[agreementId];
        if (claimScope & 1 != 0) {
            maxClaim = _mockClaimForTerms(a, a.activeTerms);
        }
        if (claimScope & 2 != 0) {
            uint256 pendingClaim = _mockClaimForTerms(a, a.pendingTerms);
            if (pendingClaim > maxClaim) maxClaim = pendingClaim;
        }
    }

    function _mockClaimForTerms(
        AgreementStorage storage a,
        IRecurringCollector.AgreementTerms memory terms
    ) private view returns (uint256) {
        if (terms.endsAt == 0) return 0;
        uint256 collectionStart;
        uint256 collectionEnd;

        uint16 s = a.state;
        bool isRegistered = (s & REGISTERED) != 0;
        bool isAccepted = (s & ACCEPTED) != 0;
        bool isTerminated = (s & NOTICE_GIVEN) != 0;
        bool isByPayer = (s & BY_PAYER) != 0;

        if (isRegistered && !isAccepted && !isTerminated) {
            // Offered (REGISTERED only)
            if (a.dataService == address(0)) return 0;
            if (terms.deadline != 0 && block.timestamp > terms.deadline) return 0;
            collectionStart = block.timestamp;
            collectionEnd = terms.endsAt;
        } else if (isRegistered && isAccepted && !isTerminated) {
            // Accepted (REGISTERED | ACCEPTED)
            collectionStart = 0 < a.lastCollectionAt ? a.lastCollectionAt : a.acceptedAt;
            collectionEnd = terms.endsAt;
        } else if (isRegistered && isAccepted && isTerminated && isByPayer) {
            // CanceledByPayer (REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PAYER)
            collectionStart = 0 < a.lastCollectionAt ? a.lastCollectionAt : a.acceptedAt;
            collectionEnd = a.collectableUntil < terms.endsAt ? a.collectableUntil : terms.endsAt;
        } else {
            return 0;
        }

        if (collectionEnd <= collectionStart) return 0;
        uint256 windowSeconds = collectionEnd - collectionStart;
        uint256 maxSeconds = windowSeconds < terms.maxSecondsPerCollection
            ? windowSeconds
            : terms.maxSecondsPerCollection;
        uint256 claim = terms.maxOngoingTokensPerSecond * maxSeconds;
        if (a.lastCollectionAt == 0) claim += terms.maxInitialTokens;
        return claim;
    }

    function offer(
        uint8 offerType,
        bytes calldata data,
        uint16 /* options */
    ) external returns (IAgreementCollector.AgreementDetails memory details) {
        if (offerType == OFFER_TYPE_NEW) {
            IRecurringCollector.RecurringCollectionAgreement memory rca = abi.decode(
                data,
                (IRecurringCollector.RecurringCollectionAgreement)
            );
            // No payer check — the real collector does this, but RAM tests need to exercise
            // the payer-mismatch path in offerAgreement, which requires the mock to return
            // an arbitrary payer without reverting.
            details.agreementId = _storeOffer(rca);
            details.payer = rca.payer;
            details.dataService = rca.dataService;
            details.serviceProvider = rca.serviceProvider;
        } else if (offerType == OFFER_TYPE_UPDATE) {
            IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = abi.decode(
                data,
                (IRecurringCollector.RecurringCollectionAgreementUpdate)
            );
            _storeUpdate(rcau);
            details.agreementId = rcau.agreementId;
            AgreementStorage storage a = _agreements[rcau.agreementId];
            details.payer = a.payer;
            details.dataService = a.dataService;
            details.serviceProvider = a.serviceProvider;
        }
        // No callback to msg.sender — caller reconciles after return (see RecurringCollector callback model)
    }

    function _storeOffer(IRecurringCollector.RecurringCollectionAgreement memory rca) internal returns (bytes16) {
        bytes16 agreementId = bytes16(
            keccak256(abi.encode(rca.payer, rca.dataService, rca.serviceProvider, rca.deadline, rca.nonce))
        );
        AgreementStorage storage agreement = _agreements[agreementId];
        agreement.dataService = rca.dataService;
        agreement.payer = rca.payer;
        agreement.serviceProvider = rca.serviceProvider;
        agreement.state = REGISTERED;
        agreement.acceptedAt = 0;
        agreement.lastCollectionAt = 0;
        agreement.updateNonce = 0;
        agreement.collectableUntil = 0;
        agreement.activeTerms.deadline = rca.deadline;
        agreement.activeTerms.endsAt = rca.endsAt;
        agreement.activeTerms.maxInitialTokens = rca.maxInitialTokens;
        agreement.activeTerms.maxOngoingTokensPerSecond = rca.maxOngoingTokensPerSecond;
        agreement.activeTerms.minSecondsPerCollection = rca.minSecondsPerCollection;
        agreement.activeTerms.maxSecondsPerCollection = rca.maxSecondsPerCollection;
        agreement.activeTerms.conditions = rca.conditions;
        agreement.activeTerms.hash = keccak256(
            abi.encode("rca", rca.payer, rca.dataService, rca.serviceProvider, rca.deadline, rca.nonce, rca.endsAt)
        );
        delete agreement.pendingTerms;
        _agreementExists[agreementId] = true;
        return agreementId;
    }

    function _storeUpdate(IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau) internal {
        AgreementStorage storage agreement = _agreements[rcau.agreementId];
        // Validate nonce: must be exactly updateNonce + 1
        require(rcau.nonce == agreement.updateNonce + 1, "MockRecurringCollector: invalid nonce");
        agreement.pendingTerms.endsAt = rcau.endsAt;
        agreement.pendingTerms.maxInitialTokens = rcau.maxInitialTokens;
        agreement.pendingTerms.maxOngoingTokensPerSecond = rcau.maxOngoingTokensPerSecond;
        agreement.pendingTerms.minSecondsPerCollection = rcau.minSecondsPerCollection;
        agreement.pendingTerms.maxSecondsPerCollection = rcau.maxSecondsPerCollection;
        agreement.pendingTerms.conditions = rcau.conditions;
        agreement.pendingTerms.hash = keccak256(abi.encode("rcau", rcau.agreementId, rcau.nonce, rcau.endsAt));
        agreement.updateNonce = rcau.nonce;
    }

    function cancel(bytes16 agreementId, bytes32 termsHash, uint16 /* options */) external {
        AgreementStorage storage agreement = _agreements[agreementId];
        if (termsHash == agreement.pendingTerms.hash && agreement.pendingTerms.endsAt > 0) {
            delete agreement.pendingTerms;
        } else {
            _cancelInternal(agreementId, BY_PAYER);
        }
        // No callback to msg.sender — caller reconciles after return (see RecurringCollector callback model)
    }

    function _cancelInternal(bytes16 agreementId, uint16 byFlag) private {
        AgreementStorage storage agreement = _agreements[agreementId];
        agreement.collectableUntil = uint64(block.timestamp);
        bool isAccepted = (agreement.state & ACCEPTED) != 0;
        if (!isAccepted) {
            // Pre-accept cancel (Withdrawn): REGISTERED | NOTICE_GIVEN | SETTLED
            agreement.state = REGISTERED | NOTICE_GIVEN | SETTLED;
        } else if (byFlag == BY_PROVIDER) {
            // Provider cancel: REGISTERED | ACCEPTED | NOTICE_GIVEN | SETTLED | BY_PROVIDER
            agreement.state = REGISTERED | ACCEPTED | NOTICE_GIVEN | SETTLED | BY_PROVIDER;
        } else {
            // Payer cancel: REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PAYER
            agreement.state = REGISTERED | ACCEPTED | NOTICE_GIVEN | byFlag;
        }
        delete agreement.pendingTerms;
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
        // Delegated to helper to avoid stack-too-deep without optimizer (12 fields exceeds EVM stack limit)
        return _hashRCAHelper(
            rca.deadline, rca.endsAt, rca.payer, rca.dataService,
            rca.serviceProvider, rca.maxInitialTokens,
            rca.maxOngoingTokensPerSecond, rca.minSecondsPerCollection,
            rca.maxSecondsPerCollection, rca.conditions, rca.nonce, rca.metadata
        );
    }

    function _hashRCAHelper(
        uint64 deadline, uint64 endsAt, address payer, address dataService,
        address serviceProvider, uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond, uint32 minSecondsPerCollection,
        uint32 maxSecondsPerCollection, uint16 conditions, uint256 nonce, bytes memory metadata
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(
            deadline, endsAt, payer, dataService, serviceProvider, maxInitialTokens,
            maxOngoingTokensPerSecond, minSecondsPerCollection, maxSecondsPerCollection,
            conditions, nonce, metadata
        ));
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
                    rcau.conditions,
                    rcau.nonce,
                    rcau.metadata
                )
            );
    }
}

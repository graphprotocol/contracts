// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

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
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IGraphToken } from "../../../contracts/common/IGraphToken.sol";
import { RecurringAgreementManager } from "../../../contracts/agreement/RecurringAgreementManager.sol";
import { RecurringAgreementHelper } from "../../../contracts/agreement/RecurringAgreementHelper.sol";
import { MockGraphToken } from "./mocks/MockGraphToken.sol";
import { MockPaymentsEscrow } from "./mocks/MockPaymentsEscrow.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

/// @notice Shared test setup for RecurringAgreementManager tests.
contract RecurringAgreementManagerSharedTest is Test {
    // -- Contracts --
    MockGraphToken internal token;
    MockPaymentsEscrow internal paymentsEscrow;
    MockRecurringCollector internal recurringCollector;
    RecurringAgreementManager internal agreementManager;
    RecurringAgreementHelper internal agreementHelper;

    // -- Accounts --
    address internal governor;
    address internal operator;
    address internal indexer;
    address internal dataService;

    // -- Constants --
    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant DATA_SERVICE_ROLE = keccak256("DATA_SERVICE_ROLE");
    bytes32 internal constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");
    bytes32 internal constant AGREEMENT_MANAGER_ROLE = keccak256("AGREEMENT_MANAGER_ROLE");

    function setUp() public virtual {
        governor = makeAddr("governor");
        operator = makeAddr("operator");
        indexer = makeAddr("indexer");

        // Deploy mocks
        token = new MockGraphToken();
        paymentsEscrow = new MockPaymentsEscrow(address(token));
        recurringCollector = new MockRecurringCollector();
        dataService = makeAddr("subgraphService");

        // Deploy RecurringAgreementManager behind proxy
        RecurringAgreementManager impl = new RecurringAgreementManager(
            IGraphToken(address(token)),
            IPaymentsEscrow(address(paymentsEscrow))
        );
        bytes memory initData = abi.encodeCall(RecurringAgreementManager.initialize, (governor));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(this), // proxy admin
            initData
        );
        agreementManager = RecurringAgreementManager(address(proxy));

        // Deploy RecurringAgreementHelper pointing at the manager
        agreementHelper = new RecurringAgreementHelper(address(agreementManager), token);

        // Grant roles
        vm.startPrank(governor);
        agreementManager.grantRole(OPERATOR_ROLE, operator);
        agreementManager.grantRole(DATA_SERVICE_ROLE, dataService);
        agreementManager.grantRole(COLLECTOR_ROLE, address(recurringCollector));
        vm.stopPrank();

        // Operator grants AGREEMENT_MANAGER_ROLE to itself (OPERATOR_ROLE is its admin)
        vm.prank(operator);
        agreementManager.grantRole(AGREEMENT_MANAGER_ROLE, operator);

        // Label addresses for trace output
        vm.label(address(token), "GraphToken");
        vm.label(address(paymentsEscrow), "PaymentsEscrow");
        vm.label(address(recurringCollector), "RecurringCollector");
        vm.label(address(agreementManager), "RecurringAgreementManager");
        vm.label(address(agreementHelper), "RecurringAgreementHelper");
        vm.label(dataService, "SubgraphService");
    }

    // -- Helpers --

    /// @notice Get the default recurring collector as a typed IRecurringCollector
    function _collector() internal view returns (IRecurringCollector) {
        return IRecurringCollector(address(recurringCollector));
    }

    /// @notice Create a standard RCA with RecurringAgreementManager as payer
    function _makeRCA(
        uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond,
        uint32 minSecondsPerCollection,
        uint32 maxSecondsPerCollection,
        uint64 endsAt
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: endsAt,
                payer: address(agreementManager),
                dataService: dataService,
                serviceProvider: indexer,
                maxInitialTokens: maxInitialTokens,
                maxOngoingTokensPerSecond: maxOngoingTokensPerSecond,
                minSecondsPerCollection: minSecondsPerCollection,
                maxSecondsPerCollection: maxSecondsPerCollection,
                conditions: 0,
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });
    }

    /// @notice Create a standard RCA and compute its agreementId
    function _makeRCAWithId(
        uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond,
        uint32 maxSecondsPerCollection,
        uint64 endsAt
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) {
        rca = _makeRCA(maxInitialTokens, maxOngoingTokensPerSecond, 60, maxSecondsPerCollection, endsAt);
        agreementId = recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
    }

    /// @notice Offer an RCA via the operator and return the agreementId
    function _offerAgreement(IRecurringCollector.RecurringCollectionAgreement memory rca) internal returns (bytes16) {
        // Fund RecurringAgreementManager with enough tokens
        token.mint(address(agreementManager), 1_000_000 ether);

        vm.prank(operator);
        return agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));
    }

    /// @notice Create a standard RCAU for an existing agreement
    function _makeRCAU(
        bytes16 agreementId,
        uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond,
        uint32 minSecondsPerCollection,
        uint32 maxSecondsPerCollection,
        uint64 endsAt,
        uint32 nonce
    ) internal pure returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        return
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0, // Not used for unsigned path
                endsAt: endsAt,
                maxInitialTokens: maxInitialTokens,
                maxOngoingTokensPerSecond: maxOngoingTokensPerSecond,
                minSecondsPerCollection: minSecondsPerCollection,
                maxSecondsPerCollection: maxSecondsPerCollection,
                conditions: 0,
                minSecondsPayerCancellationNotice: 0,
                nonce: nonce,
                metadata: ""
            });
    }

    /// @notice Offer an RCAU via the operator
    function _offerAgreementUpdate(IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau) internal {
        vm.prank(operator);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_UPDATE, abi.encode(rcau));
    }

    /// @notice Cancel an agreement by reading the activeTerms hash from the collector
    /// @return gone True if the agreement was removed (no longer tracked)
    function _cancelAgreement(bytes16 agreementId) internal returns (bool gone) {
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(operator);
        agreementManager.cancelAgreement(address(recurringCollector), agreementId, activeHash, 0);
        // cancelAgreement is void; the callback handles reconciliation.
        // Check if the agreement was removed by looking at the provider field.
        return agreementManager.getAgreementInfo(address(recurringCollector), agreementId).provider == address(0);
    }

    /// @notice Cancel a pending update by reading the pendingTerms hash from the collector
    /// @return gone True if the agreement was removed (no longer tracked)
    function _cancelPendingUpdate(bytes16 agreementId) internal returns (bool gone) {
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        vm.prank(operator);
        agreementManager.cancelAgreement(address(recurringCollector), agreementId, pendingHash, 0);
        return agreementManager.getAgreementInfo(address(recurringCollector), agreementId).provider == address(0);
    }

    /// @notice Build active terms from an RCA
    function _activeTermsFromRCA(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal pure returns (IRecurringCollector.AgreementTerms memory) {
        return IRecurringCollector.AgreementTerms({
            deadline: 0,
            endsAt: rca.endsAt,
            maxInitialTokens: rca.maxInitialTokens,
            maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
            minSecondsPerCollection: rca.minSecondsPerCollection,
            maxSecondsPerCollection: rca.maxSecondsPerCollection,
            conditions: 0,
            minSecondsPayerCancellationNotice: 0,
            hash: bytes32(0),
            metadata: ""
        });
    }

    /// @notice Build empty pending terms
    function _emptyTerms() internal pure returns (IRecurringCollector.AgreementTerms memory) {
        return IRecurringCollector.AgreementTerms({
            deadline: 0,
            endsAt: 0,
            maxInitialTokens: 0,
            maxOngoingTokensPerSecond: 0,
            minSecondsPerCollection: 0,
            maxSecondsPerCollection: 0,
            conditions: 0,
            minSecondsPayerCancellationNotice: 0,
            hash: bytes32(0),
            metadata: ""
        });
    }

    /// @notice Build agreement data from common parameters
    function _buildAgreementStorage(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint16 state,
        uint64 acceptedAt,
        uint64 collectableUntil,
        uint64 lastCollectionAt
    ) internal pure returns (MockRecurringCollector.AgreementStorage memory) {
        return MockRecurringCollector.AgreementStorage({
            dataService: rca.dataService,
            payer: rca.payer,
            serviceProvider: rca.serviceProvider,
            acceptedAt: acceptedAt,
            lastCollectionAt: lastCollectionAt,
            updateNonce: 0,
            collectableUntil: collectableUntil,
            state: state,
            activeTerms: _activeTermsFromRCA(rca),
            pendingTerms: _emptyTerms()
        });
    }

    /// @notice Set up a mock agreement in RecurringCollector as Accepted
    function _setAgreementAccepted(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint64 acceptedAt
    ) internal {
        recurringCollector.setAgreement(agreementId, _buildAgreementStorage(rca, REGISTERED | ACCEPTED, acceptedAt, 0, 0));
    }

    /// @notice Set up a mock agreement as CanceledByServiceProvider
    function _setAgreementCanceledBySP(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal {
        recurringCollector.setAgreement(
            agreementId,
            _buildAgreementStorage(
                rca,
                REGISTERED | ACCEPTED | NOTICE_GIVEN | SETTLED | BY_PROVIDER,
                uint64(block.timestamp),
                uint64(block.timestamp),
                0
            )
        );
    }

    /// @notice Set up a mock agreement as CanceledByPayer
    function _setAgreementCanceledByPayer(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint64 acceptedAt,
        uint64 collectableUntil,
        uint64 lastCollectionAt
    ) internal {
        recurringCollector.setAgreement(
            agreementId,
            _buildAgreementStorage(rca, REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PAYER, acceptedAt, collectableUntil, lastCollectionAt)
        );
    }

    /// @notice Set up a mock agreement as having been collected
    function _setAgreementCollected(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint64 acceptedAt,
        uint64 lastCollectionAt
    ) internal {
        recurringCollector.setAgreement(
            agreementId,
            _buildAgreementStorage(rca, REGISTERED | ACCEPTED, acceptedAt, 0, lastCollectionAt)
        );
    }
}

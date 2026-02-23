// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IndexingAgreementManager } from "../../../contracts/allocate/IndexingAgreementManager.sol";
import { MockGraphToken } from "./mocks/MockGraphToken.sol";
import { MockPaymentsEscrow } from "./mocks/MockPaymentsEscrow.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";
import { MockSubgraphService } from "./mocks/MockSubgraphService.sol";

/// @notice Shared test setup for IndexingAgreementManager tests.
contract IndexingAgreementManagerSharedTest is Test {
    // -- Contracts --
    MockGraphToken internal token;
    MockPaymentsEscrow internal paymentsEscrow;
    MockRecurringCollector internal recurringCollector;
    MockSubgraphService internal mockSubgraphService;
    IndexingAgreementManager internal agreementManager;

    // -- Accounts --
    address internal governor;
    address internal operator;
    address internal indexer;
    address internal dataService;

    // -- Constants --
    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    function setUp() public virtual {
        governor = makeAddr("governor");
        operator = makeAddr("operator");
        indexer = makeAddr("indexer");

        // Deploy mocks
        token = new MockGraphToken();
        paymentsEscrow = new MockPaymentsEscrow(address(token));
        recurringCollector = new MockRecurringCollector();
        mockSubgraphService = new MockSubgraphService();
        dataService = address(mockSubgraphService);

        // Deploy IndexingAgreementManager behind proxy
        IndexingAgreementManager impl = new IndexingAgreementManager(
            address(token),
            address(paymentsEscrow),
            address(recurringCollector)
        );
        bytes memory initData = abi.encodeCall(IndexingAgreementManager.initialize, (governor));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(this), // proxy admin
            initData
        );
        agreementManager = IndexingAgreementManager(address(proxy));

        // Grant operator role
        vm.prank(governor);
        agreementManager.grantRole(OPERATOR_ROLE, operator);

        // Label addresses for trace output
        vm.label(address(token), "GraphToken");
        vm.label(address(paymentsEscrow), "PaymentsEscrow");
        vm.label(address(recurringCollector), "RecurringCollector");
        vm.label(address(agreementManager), "IndexingAgreementManager");
        vm.label(address(mockSubgraphService), "SubgraphService");
    }

    // -- Helpers --

    /// @notice Create a standard RCA with IndexingAgreementManager as payer
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
        // Fund IndexingAgreementManager with enough tokens
        token.mint(address(agreementManager), 1_000_000 ether);

        vm.prank(operator);
        return agreementManager.offerAgreement(rca);
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
                nonce: nonce,
                metadata: ""
            });
    }

    /// @notice Offer an RCAU via the operator
    function _offerAgreementUpdate(
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau
    ) internal returns (bytes16) {
        vm.prank(operator);
        return agreementManager.offerAgreementUpdate(rcau);
    }

    /// @notice Set up a mock agreement in RecurringCollector as Accepted
    function _setAgreementAccepted(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint64 acceptedAt
    ) internal {
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: acceptedAt,
                lastCollectionAt: 0,
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                updateNonce: 0,
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );
    }

    /// @notice Set up a mock agreement as CanceledByServiceProvider
    function _setAgreementCanceledBySP(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal {
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: uint64(block.timestamp),
                lastCollectionAt: 0,
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                updateNonce: 0,
                canceledAt: uint64(block.timestamp),
                state: IRecurringCollector.AgreementState.CanceledByServiceProvider
            })
        );
    }

    /// @notice Set up a mock agreement as CanceledByPayer
    function _setAgreementCanceledByPayer(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint64 acceptedAt,
        uint64 canceledAt,
        uint64 lastCollectionAt
    ) internal {
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: acceptedAt,
                lastCollectionAt: lastCollectionAt,
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                updateNonce: 0,
                canceledAt: canceledAt,
                state: IRecurringCollector.AgreementState.CanceledByPayer
            })
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
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: acceptedAt,
                lastCollectionAt: lastCollectionAt,
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                updateNonce: 0,
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );
    }
}

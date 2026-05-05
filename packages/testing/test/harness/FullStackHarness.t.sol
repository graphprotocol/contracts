// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

// -- Real contracts (all on the critical path) --
import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";
import { GraphProxy } from "@graphprotocol/contracts/contracts/upgrades/GraphProxy.sol";
import { GraphProxyAdmin } from "@graphprotocol/contracts/contracts/upgrades/GraphProxyAdmin.sol";
import { HorizonStaking } from "horizon/staking/HorizonStaking.sol";
import { GraphPayments } from "horizon/payments/GraphPayments.sol";
import { PaymentsEscrow } from "horizon/payments/PaymentsEscrow.sol";
import { RecurringCollector } from "horizon/payments/collectors/RecurringCollector.sol";
import { SubgraphService } from "subgraph-service/SubgraphService.sol";
import { DisputeManager } from "subgraph-service/DisputeManager.sol";
import { IssuanceAllocator } from "issuance/allocate/IssuanceAllocator.sol";
import { RecurringAgreementManager } from "issuance/agreement/RecurringAgreementManager.sol";
import { RecurringAgreementHelper } from "issuance/agreement/RecurringAgreementHelper.sol";

// -- Interfaces --
import { IHorizonStaking } from "@graphprotocol/interfaces/contracts/horizon/IHorizonStaking.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import {
    IAgreementCollector,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IGraphToken as IssuanceIGraphToken } from "issuance/common/IGraphToken.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

// -- Mocks (only for contracts NOT on the payment/agreement critical path) --
import { MockGRTToken } from "subgraph-service-test/unit/mocks/MockGRTToken.sol";
import { MockCuration } from "subgraph-service-test/unit/mocks/MockCuration.sol";
import { MockEpochManager } from "subgraph-service-test/unit/mocks/MockEpochManager.sol";
import { MockRewardsManager } from "subgraph-service-test/unit/mocks/MockRewardsManager.sol";

// -- Helpers --
import { IndexingAgreement } from "subgraph-service/libraries/IndexingAgreement.sol";
import { RecurringCollectorHelper } from "horizon-test/unit/payments/recurring-collector/RecurringCollectorHelper.t.sol";

/// @title FullStackHarness
/// @notice Deploys the complete protocol stack for cross-package integration tests:
///
/// Real contracts (on critical path):
///   - Controller, GraphProxyAdmin, HorizonStaking
///   - GraphPayments, PaymentsEscrow
///   - RecurringCollector
///   - SubgraphService, DisputeManager
///   - RecurringAgreementManager, IssuanceAllocator, RecurringAgreementHelper
///
/// Mocks (not on critical path):
///   - MockGRTToken (ERC20, slightly cheaper than proxied token)
///   - MockCuration (signal tracking for reward calculations)
///   - MockEpochManager (epoch/block tracking)
///   - MockRewardsManager (indexing reward minting)
abstract contract FullStackHarness is Test {
    // -- Constants --
    uint256 internal constant MINIMUM_PROVISION_TOKENS = 1000 ether;
    uint32 internal constant DELEGATION_RATIO = 16;
    uint256 internal constant STAKE_TO_FEES_RATIO = 2;
    uint256 internal constant PROTOCOL_PAYMENT_CUT = 10000; // 1% in PPM
    uint256 internal constant WITHDRAW_ESCROW_THAWING_PERIOD = 60;
    uint64 internal constant DISPUTE_PERIOD = 7 days;
    uint256 internal constant DISPUTE_DEPOSIT = 100 ether;
    uint32 internal constant FISHERMAN_REWARD_PERCENTAGE = 500000; // 50%
    uint32 internal constant MAX_SLASHING_PERCENTAGE = 100000; // 10%
    uint64 internal constant MAX_WAIT_PERIOD = 28 days;
    uint256 internal constant REVOKE_SIGNER_THAWING_PERIOD = 7 days;
    uint256 internal constant REWARDS_PER_SIGNAL = 10000;
    uint256 internal constant REWARDS_PER_SUBGRAPH_ALLOCATION_UPDATE = 1000;
    uint256 internal constant EPOCH_LENGTH = 1;
    uint256 internal constant MAX_POI_STALENESS = 28 days;
    uint256 internal constant CURATION_CUT = 10000;

    // -- RAM role constants --
    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant DATA_SERVICE_ROLE = keccak256("DATA_SERVICE_ROLE");
    bytes32 internal constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");
    bytes32 internal constant AGREEMENT_MANAGER_ROLE = keccak256("AGREEMENT_MANAGER_ROLE");

    // -- Real contracts --
    Controller internal controller;
    GraphProxyAdmin internal proxyAdmin;
    IHorizonStaking internal staking;
    GraphPayments internal graphPayments;
    PaymentsEscrow internal escrow;
    RecurringCollector internal recurringCollector;
    SubgraphService internal subgraphService;
    DisputeManager internal disputeManager;
    IssuanceAllocator internal issuanceAllocator;
    RecurringAgreementManager internal ram;
    RecurringAgreementHelper internal ramHelper;
    address internal recurringCollectorProxyAdmin;

    // -- Mocks --
    MockGRTToken internal token;
    MockCuration internal curation;
    MockEpochManager internal epochManager;
    MockRewardsManager internal rewardsManager;

    // -- Helpers --
    RecurringCollectorHelper internal rcHelper;

    // -- Accounts --
    address internal governor;
    address internal deployer;
    address internal operator; // RAM operator
    address internal arbitrator;
    address internal pauseGuardian;

    function setUp() public virtual {
        governor = makeAddr("governor");
        deployer = makeAddr("deployer");
        operator = makeAddr("operator");
        arbitrator = makeAddr("arbitrator");
        pauseGuardian = makeAddr("pauseGuardian");

        // Fund accounts with ETH
        vm.deal(governor, 100 ether);
        vm.deal(deployer, 100 ether);

        _deployProtocol();
        _deployRAMStack();
        _configureProtocol();
    }

    // ── Protocol deployment (follows SubgraphBaseTest pattern) ──────────

    function _deployProtocol() private {
        vm.startPrank(governor);
        proxyAdmin = new GraphProxyAdmin();
        controller = new Controller();
        vm.stopPrank();

        vm.startPrank(deployer);
        token = new MockGRTToken();
        GraphProxy stakingProxy = new GraphProxy(address(0), address(proxyAdmin));
        rewardsManager = new MockRewardsManager(token, REWARDS_PER_SIGNAL, REWARDS_PER_SUBGRAPH_ALLOCATION_UPDATE);
        curation = new MockCuration();
        epochManager = new MockEpochManager();

        // Predict GraphPayments and PaymentsEscrow addresses using actual creation code.
        // We use type(...).creationCode instead of vm.getCode to get the exact bytecode
        // that will be used by CREATE2, avoiding metadata hash mismatches across packages.
        bytes32 saltGP = keccak256("GraphPaymentsSalt");
        bytes memory gpCreation = type(GraphPayments).creationCode;
        address predictedGP = vm.computeCreate2Address(
            saltGP,
            keccak256(bytes.concat(gpCreation, abi.encode(address(controller), PROTOCOL_PAYMENT_CUT))),
            deployer
        );

        bytes32 saltEscrow = keccak256("GraphEscrowSalt");
        bytes memory escrowCreation = type(PaymentsEscrow).creationCode;
        address predictedEscrow = vm.computeCreate2Address(
            saltEscrow,
            keccak256(bytes.concat(escrowCreation, abi.encode(address(controller), WITHDRAW_ESCROW_THAWING_PERIOD))),
            deployer
        );

        // Register in controller (GraphDirectory reads immutably at construction)
        vm.startPrank(governor);
        controller.setContractProxy(keccak256("GraphToken"), address(token));
        controller.setContractProxy(keccak256("Staking"), address(stakingProxy));
        controller.setContractProxy(keccak256("RewardsManager"), address(rewardsManager));
        controller.setContractProxy(keccak256("GraphPayments"), predictedGP);
        controller.setContractProxy(keccak256("PaymentsEscrow"), predictedEscrow);
        controller.setContractProxy(keccak256("EpochManager"), address(epochManager));
        controller.setContractProxy(keccak256("GraphTokenGateway"), makeAddr("GraphTokenGateway"));
        controller.setContractProxy(keccak256("GraphProxyAdmin"), makeAddr("GraphProxyAdmin"));
        controller.setContractProxy(keccak256("Curation"), address(curation));
        vm.stopPrank();

        // Deploy DisputeManager
        vm.startPrank(deployer);
        address dmImpl = address(new DisputeManager(address(controller)));
        address dmProxy = address(
            new TransparentUpgradeableProxy(
                dmImpl,
                governor,
                abi.encodeCall(
                    DisputeManager.initialize,
                    (
                        deployer,
                        arbitrator,
                        DISPUTE_PERIOD,
                        DISPUTE_DEPOSIT,
                        FISHERMAN_REWARD_PERCENTAGE,
                        MAX_SLASHING_PERCENTAGE
                    )
                )
            )
        );
        disputeManager = DisputeManager(dmProxy);
        disputeManager.transferOwnership(governor);

        // Deploy RecurringCollector behind proxy
        RecurringCollector rcImpl = new RecurringCollector(address(controller), REVOKE_SIGNER_THAWING_PERIOD);
        TransparentUpgradeableProxy rcProxy = new TransparentUpgradeableProxy(
            address(rcImpl),
            governor,
            abi.encodeCall(RecurringCollector.initialize, ("RecurringCollector", "1"))
        );
        recurringCollector = RecurringCollector(address(rcProxy));
        recurringCollectorProxyAdmin = address(uint160(uint256(vm.load(address(rcProxy), ERC1967Utils.ADMIN_SLOT))));

        // Deploy SubgraphService
        address ssImpl = address(
            new SubgraphService(
                address(controller),
                address(disputeManager),
                makeAddr("GraphTallyCollector"), // stub — not needed for indexing fee tests
                address(curation),
                address(recurringCollector)
            )
        );
        address ssProxy = address(
            new TransparentUpgradeableProxy(
                ssImpl,
                governor,
                abi.encodeCall(
                    SubgraphService.initialize,
                    (deployer, MINIMUM_PROVISION_TOKENS, DELEGATION_RATIO, STAKE_TO_FEES_RATIO)
                )
            )
        );
        subgraphService = SubgraphService(ssProxy);

        // Deploy HorizonStaking implementation and wire to proxy
        HorizonStaking stakingBase = new HorizonStaking(address(controller), address(subgraphService));
        vm.stopPrank();

        // Deploy GraphPayments and PaymentsEscrow at predicted addresses
        vm.startPrank(deployer);
        graphPayments = new GraphPayments{ salt: saltGP }(address(controller), PROTOCOL_PAYMENT_CUT);
        escrow = new PaymentsEscrow{ salt: saltEscrow }(address(controller), WITHDRAW_ESCROW_THAWING_PERIOD);
        vm.stopPrank();

        // Wire staking proxy
        vm.startPrank(governor);
        disputeManager.setSubgraphService(address(subgraphService));
        proxyAdmin.upgrade(stakingProxy, address(stakingBase));
        proxyAdmin.acceptProxy(stakingBase, stakingProxy);
        staking = IHorizonStaking(address(stakingProxy));
        vm.stopPrank();

        // RecurringCollectorHelper
        rcHelper = new RecurringCollectorHelper(recurringCollector, recurringCollectorProxyAdmin);
    }

    // ── RAM + IssuanceAllocator deployment ──────────────────────────────

    function _deployRAMStack() private {
        vm.startPrank(deployer);

        // Deploy IssuanceAllocator behind proxy
        IssuanceAllocator allocatorImpl = new IssuanceAllocator(IssuanceIGraphToken(address(token)));
        TransparentUpgradeableProxy allocatorProxy = new TransparentUpgradeableProxy(
            address(allocatorImpl),
            governor,
            abi.encodeCall(IssuanceAllocator.initialize, (governor))
        );
        issuanceAllocator = IssuanceAllocator(address(allocatorProxy));

        // Deploy RecurringAgreementManager behind proxy
        RecurringAgreementManager ramImpl = new RecurringAgreementManager(
            IssuanceIGraphToken(address(token)),
            IPaymentsEscrow(address(escrow))
        );
        TransparentUpgradeableProxy ramProxy = new TransparentUpgradeableProxy(
            address(ramImpl),
            governor,
            abi.encodeCall(RecurringAgreementManager.initialize, (governor))
        );
        ram = RecurringAgreementManager(address(ramProxy));

        // Deploy RecurringAgreementHelper (stateless, no proxy needed)
        ramHelper = new RecurringAgreementHelper(address(ram), IERC20(address(token)));

        vm.stopPrank();

        // Configure RAM roles and issuance
        vm.startPrank(governor);
        ram.grantRole(OPERATOR_ROLE, operator);
        ram.grantRole(DATA_SERVICE_ROLE, address(subgraphService));
        ram.grantRole(COLLECTOR_ROLE, address(recurringCollector));
        ram.setIssuanceAllocator(address(issuanceAllocator));

        issuanceAllocator.setIssuancePerBlock(1 ether);
        issuanceAllocator.setTargetAllocation(IIssuanceTarget(address(ram)), 1 ether);
        vm.stopPrank();

        vm.prank(operator);
        ram.grantRole(AGREEMENT_MANAGER_ROLE, operator);
    }

    // ── Protocol configuration ─────────────────────────────────────────

    function _configureProtocol() private {
        vm.startPrank(governor);
        staking.setMaxThawingPeriod(MAX_WAIT_PERIOD);
        controller.setPaused(false);
        vm.stopPrank();

        vm.startPrank(deployer);
        subgraphService.transferOwnership(governor);
        vm.stopPrank();

        vm.startPrank(governor);
        epochManager.setEpochLength(EPOCH_LENGTH);
        subgraphService.setMaxPOIStaleness(MAX_POI_STALENESS);
        subgraphService.setCurationCut(CURATION_CUT);
        subgraphService.setPauseGuardian(pauseGuardian, true);
        vm.stopPrank();

        // Labels
        vm.label(address(token), "GraphToken");
        vm.label(address(controller), "Controller");
        vm.label(address(staking), "HorizonStaking");
        vm.label(address(graphPayments), "GraphPayments");
        vm.label(address(escrow), "PaymentsEscrow");
        vm.label(address(recurringCollector), "RecurringCollector");
        vm.label(address(subgraphService), "SubgraphService");
        vm.label(address(disputeManager), "DisputeManager");
        vm.label(address(issuanceAllocator), "IssuanceAllocator");
        vm.label(address(ram), "RecurringAgreementManager");
        vm.label(address(ramHelper), "RecurringAgreementHelper");
    }

    // ── Indexer setup helpers ──────────────────────────────────────────

    struct IndexerSetup {
        address addr;
        address allocationId;
        uint256 allocationKey;
        bytes32 subgraphDeploymentId;
        uint256 provisionTokens;
    }

    /// @notice Create a fully provisioned and registered indexer with an open allocation
    function _setupIndexer(
        string memory label,
        bytes32 subgraphDeploymentId,
        uint256 provisionTokens
    ) internal returns (IndexerSetup memory indexer) {
        indexer.addr = makeAddr(label);
        (indexer.allocationId, indexer.allocationKey) = makeAddrAndKey(string.concat(label, "-allocation"));
        indexer.subgraphDeploymentId = subgraphDeploymentId;
        indexer.provisionTokens = provisionTokens;

        // Fund and provision
        _mintTokens(indexer.addr, provisionTokens);
        vm.startPrank(indexer.addr);
        token.approve(address(staking), provisionTokens);
        staking.stakeTo(indexer.addr, provisionTokens);
        staking.provision(
            indexer.addr,
            address(subgraphService),
            provisionTokens,
            FISHERMAN_REWARD_PERCENTAGE,
            DISPUTE_PERIOD
        );

        // Register
        subgraphService.register(indexer.addr, abi.encode("url", "geoHash", address(0)));

        // Create allocation
        bytes32 digest = subgraphService.encodeAllocationProof(indexer.addr, indexer.allocationId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(indexer.allocationKey, digest);
        bytes memory allocationData = abi.encode(
            subgraphDeploymentId,
            provisionTokens,
            indexer.allocationId,
            abi.encodePacked(r, s, v)
        );
        subgraphService.startService(indexer.addr, allocationData);

        // Set payments destination to indexer address (so tokens flow to indexer.addr)
        subgraphService.setPaymentsDestination(indexer.addr);
        vm.stopPrank();
    }

    // ── RAM agreement helpers ──────────────────────────────────────────

    /// @notice Build an RCA with RAM as payer, targeting a specific indexer + SS
    function _buildRCA(
        IndexerSetup memory indexer,
        uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond,
        uint32 maxSecondsPerCollection,
        IndexingAgreement.IndexingAgreementTermsV1 memory terms
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(ram),
                dataService: address(subgraphService),
                serviceProvider: indexer.addr,
                maxInitialTokens: maxInitialTokens,
                maxOngoingTokensPerSecond: maxOngoingTokensPerSecond,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: maxSecondsPerCollection,
                nonce: 1,
                conditions: 0,
                metadata: abi.encode(
                    IndexingAgreement.AcceptIndexingAgreementMetadata({
                        subgraphDeploymentId: indexer.subgraphDeploymentId,
                        version: IIndexingAgreement.IndexingAgreementVersion.V1,
                        terms: abi.encode(terms)
                    })
                )
            });
    }

    /// @notice Build an RCA with custom nonce and conditions
    function _buildRCAEx(
        IndexerSetup memory indexer,
        uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond,
        uint32 maxSecondsPerCollection,
        IndexingAgreement.IndexingAgreementTermsV1 memory terms,
        uint256 nonce,
        uint16 conditions
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(ram),
                dataService: address(subgraphService),
                serviceProvider: indexer.addr,
                maxInitialTokens: maxInitialTokens,
                maxOngoingTokensPerSecond: maxOngoingTokensPerSecond,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: maxSecondsPerCollection,
                nonce: nonce,
                conditions: conditions,
                metadata: abi.encode(
                    IndexingAgreement.AcceptIndexingAgreementMetadata({
                        subgraphDeploymentId: indexer.subgraphDeploymentId,
                        version: IIndexingAgreement.IndexingAgreementVersion.V1,
                        terms: abi.encode(terms)
                    })
                )
            });
    }

    /// @notice Add tokens to an indexer's provision for stake locking
    function _addProvisionTokens(IndexerSetup memory indexer, uint256 amount) internal {
        _mintTokens(indexer.addr, amount);
        vm.startPrank(indexer.addr);
        token.approve(address(staking), amount);
        staking.stakeTo(indexer.addr, amount);
        staking.addToProvision(indexer.addr, address(subgraphService), amount);
        vm.stopPrank();
    }

    /// @notice Fund RAM and offer a new agreement
    function _ramOffer(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16 agreementId) {
        _mintTokens(address(ram), 1_000_000 ether);
        vm.prank(operator);
        agreementId = ram.offerAgreement(
            IAgreementCollector(address(recurringCollector)),
            OFFER_TYPE_NEW,
            abi.encode(rca)
        );
    }

    /// @notice Accept an offered agreement via SubgraphService (unsigned/contract-approved path)
    function _ssAccept(
        IndexerSetup memory indexer,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16 agreementId) {
        vm.prank(indexer.addr);
        agreementId = subgraphService.acceptIndexingAgreement(indexer.allocationId, rca, "");
    }

    /// @notice Offer via RAM + accept via SS in one call
    function _offerAndAccept(
        IndexerSetup memory indexer,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16 agreementId) {
        _ramOffer(rca);
        agreementId = _ssAccept(indexer, rca);
    }

    /// @notice Collect indexing fees through SS → RC → GraphPayments → escrow
    function _collectIndexingFees(
        IndexerSetup memory indexer,
        bytes16 agreementId,
        uint256 entities,
        bytes32 poi,
        uint256 poiBlockNumber
    ) internal returns (uint256 tokensCollected) {
        bytes memory collectData = abi.encode(
            agreementId,
            abi.encode(
                IndexingAgreement.CollectIndexingFeeDataV1({
                    entities: entities,
                    poi: poi,
                    poiBlockNumber: poiBlockNumber,
                    metadata: "",
                    maxSlippage: type(uint256).max
                })
            )
        );

        vm.prank(indexer.addr);
        tokensCollected = subgraphService.collect(indexer.addr, IGraphPayments.PaymentTypes.IndexingFee, collectData);
    }

    // ── Escrow helpers ─────────────────────────────────────────────────

    // ── Token helpers ──────────────────────────────────────────────────

    function _mintTokens(address to, uint256 amount) internal {
        token.mint(to, amount);
    }

    // ── Prank helpers ──────────────────────────────────────────────────

    function resetPrank(address msgSender) internal {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }
}

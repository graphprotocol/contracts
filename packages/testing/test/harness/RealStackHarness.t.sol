// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

// Real contracts
import { PaymentsEscrow } from "horizon/payments/PaymentsEscrow.sol";
import { RecurringCollector } from "horizon/payments/collectors/RecurringCollector.sol";
import { IssuanceAllocator } from "issuance/allocate/IssuanceAllocator.sol";
import { RecurringAgreementManager } from "issuance/agreement/RecurringAgreementManager.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";

// Use the issuance IGraphToken for RAM/allocator (IERC20 + mint)
import { IGraphToken as IssuanceIGraphToken } from "issuance/common/IGraphToken.sol";

// Interfaces
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Stubs for infra not on callback path
import { ControllerStub } from "../mocks/ControllerStub.sol";
import { HorizonStakingStub } from "../mocks/HorizonStakingStub.sol";
import { GraphTokenMock } from "../mocks/GraphTokenMock.sol";

/// @notice Deploys the real contract stack that participates in RAM callback gas:
///   - PaymentsEscrow (real) — RAM calls deposit/adjustThaw/withdraw/escrowAccounts
///   - RecurringCollector (real) — RAM calls getAgreement/getMaxNextClaim in afterCollection
///   - IssuanceAllocator (real, behind proxy) — RAM calls distributeIssuance
///   - RecurringAgreementManager (real, behind proxy) — the contract under test
///
/// Only infrastructure not on the callback path is stubbed:
///   - Controller (paused() check, contract registry)
///   - HorizonStaking (provision check in RecurringCollector.collect, not in RAM callbacks)
///   - GraphToken (bare ERC20 — ~2-5k cheaper per op than proxied real token)
abstract contract RealStackHarness is Test {
    // -- Real contracts --
    PaymentsEscrow internal paymentsEscrow;
    RecurringCollector internal recurringCollector;
    IssuanceAllocator internal issuanceAllocator;
    RecurringAgreementManager internal ram;

    // -- Stubs --
    ControllerStub internal controller;
    HorizonStakingStub internal staking;
    GraphTokenMock internal token;

    // -- Accounts --
    address internal governor;
    address internal operator;
    address internal indexer;
    address internal dataService;

    // -- Role constants --
    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant DATA_SERVICE_ROLE = keccak256("DATA_SERVICE_ROLE");
    bytes32 internal constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");
    bytes32 internal constant AGREEMENT_MANAGER_ROLE = keccak256("AGREEMENT_MANAGER_ROLE");

    function setUp() public virtual {
        governor = makeAddr("governor");
        operator = makeAddr("operator");
        indexer = makeAddr("indexer");
        dataService = makeAddr("dataService");

        // 1. Deploy stubs
        token = new GraphTokenMock();
        controller = new ControllerStub();
        staking = new HorizonStakingStub();

        // 2. Register in controller (GraphDirectory reads these immutably at construction)
        controller.register("GraphToken", address(token));
        controller.register("Staking", address(staking));

        // 3. Deploy real PaymentsEscrow behind proxy
        PaymentsEscrow escrowImpl = new PaymentsEscrow(address(controller), 1 days);
        TransparentUpgradeableProxy escrowProxy = new TransparentUpgradeableProxy(
            address(escrowImpl),
            address(this),
            abi.encodeCall(PaymentsEscrow.initialize, ())
        );
        paymentsEscrow = PaymentsEscrow(address(escrowProxy));
        controller.register("PaymentsEscrow", address(paymentsEscrow));

        // 4. Deploy real RecurringCollector behind proxy
        RecurringCollector rcImpl = new RecurringCollector(address(controller), 1);
        TransparentUpgradeableProxy rcProxy = new TransparentUpgradeableProxy(
            address(rcImpl),
            address(this),
            abi.encodeCall(RecurringCollector.initialize, ("RecurringCollector", "1"))
        );
        recurringCollector = RecurringCollector(address(rcProxy));

        // 5. Deploy real IssuanceAllocator behind proxy
        IssuanceAllocator allocatorImpl = new IssuanceAllocator(IssuanceIGraphToken(address(token)));
        TransparentUpgradeableProxy allocatorProxy = new TransparentUpgradeableProxy(
            address(allocatorImpl),
            address(this),
            abi.encodeCall(IssuanceAllocator.initialize, (governor))
        );
        issuanceAllocator = IssuanceAllocator(address(allocatorProxy));

        // 6. Deploy real RecurringAgreementManager behind proxy
        RecurringAgreementManager ramImpl = new RecurringAgreementManager(
            IssuanceIGraphToken(address(token)),
            IPaymentsEscrow(address(paymentsEscrow))
        );
        TransparentUpgradeableProxy ramProxy = new TransparentUpgradeableProxy(
            address(ramImpl),
            address(this),
            abi.encodeCall(RecurringAgreementManager.initialize, (governor))
        );
        ram = RecurringAgreementManager(address(ramProxy));

        // 7. Wire up roles
        vm.startPrank(governor);
        ram.grantRole(OPERATOR_ROLE, operator);
        ram.grantRole(DATA_SERVICE_ROLE, dataService);
        ram.grantRole(COLLECTOR_ROLE, address(recurringCollector));
        ram.setIssuanceAllocator(address(issuanceAllocator));
        // Configure allocator: set total issuance rate, then allocate to RAM
        issuanceAllocator.setIssuancePerBlock(1 ether);
        issuanceAllocator.setTargetAllocation(IIssuanceTarget(address(ram)), 1 ether);
        vm.stopPrank();

        vm.prank(operator);
        ram.grantRole(AGREEMENT_MANAGER_ROLE, operator);

        // 8. Set up staking provision so RecurringCollector allows collections
        staking.setProvision(
            indexer,
            dataService,
            IHorizonStakingTypes.Provision({
                tokens: 1000 ether,
                tokensThawing: 0,
                sharesThawing: 0,
                maxVerifierCut: 100000,
                thawingPeriod: 604800,
                createdAt: uint64(block.timestamp),
                maxVerifierCutPending: 100000,
                thawingPeriodPending: 604800,
                lastParametersStagedAt: 0,
                thawingNonce: 0
            })
        );

        // Labels
        vm.label(address(token), "GraphToken");
        vm.label(address(paymentsEscrow), "PaymentsEscrow");
        vm.label(address(recurringCollector), "RecurringCollector");
        vm.label(address(issuanceAllocator), "IssuanceAllocator");
        vm.label(address(ram), "RecurringAgreementManager");
    }

    // -- Helpers --

    /// @notice Create an RCA with RAM as payer
    function _makeRCA(
        uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond,
        uint32 maxSecondsPerCollection,
        uint64 endsAt
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: endsAt,
                payer: address(ram),
                dataService: dataService,
                serviceProvider: indexer,
                maxInitialTokens: maxInitialTokens,
                maxOngoingTokensPerSecond: maxOngoingTokensPerSecond,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: maxSecondsPerCollection,
                nonce: 1,
                metadata: ""
            });
    }

    /// @notice Offer an agreement, funding the RAM first
    function _offerAgreement(IRecurringCollector.RecurringCollectionAgreement memory rca) internal returns (bytes16) {
        token.mint(address(ram), 1_000_000 ether);
        vm.prank(operator);
        return ram.offerAgreement(rca, IRecurringCollector(address(recurringCollector)));
    }

    /// @notice Offer and accept an agreement via the unsigned path, returning the agreement ID
    function _offerAndAccept(IRecurringCollector.RecurringCollectionAgreement memory rca) internal returns (bytes16) {
        bytes16 agreementId = _offerAgreement(rca);
        vm.prank(dataService);
        recurringCollector.accept(rca, "");
        return agreementId;
    }

    /// @notice Set up a staking provision for a provider so RecurringCollector allows operations
    function _setUpProvider(address provider) internal {
        staking.setProvision(
            provider,
            dataService,
            IHorizonStakingTypes.Provision({
                tokens: 1000 ether,
                tokensThawing: 0,
                sharesThawing: 0,
                maxVerifierCut: 100000,
                thawingPeriod: 604800,
                createdAt: uint64(block.timestamp),
                maxVerifierCutPending: 100000,
                thawingPeriodPending: 604800,
                lastParametersStagedAt: 0,
                thawingNonce: 0
            })
        );
    }
}

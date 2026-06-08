// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";

import { PartialControllerMock } from "../../mocks/PartialControllerMock.t.sol";
import { HorizonStakingMock } from "../../mocks/HorizonStakingMock.t.sol";
import { PaymentsEscrowMock } from "./PaymentsEscrowMock.t.sol";
import { RecurringCollectorHelper } from "./RecurringCollectorHelper.t.sol";
import { Bounder } from "../../utils/Bounder.t.sol";

/// @notice Upgrade scenario tests for RecurringCollector (TransparentUpgradeableProxy).
contract RecurringCollectorUpgradeScenarioTest is Test, Bounder {
    RecurringCollector internal _recurringCollector;
    PaymentsEscrowMock internal _paymentsEscrow;
    HorizonStakingMock internal _horizonStaking;
    RecurringCollectorHelper internal _recurringCollectorHelper;
    address internal _proxyAdminAddr;
    address internal _proxyAdminOwner;
    address internal _controller;

    function setUp() public {
        _paymentsEscrow = new PaymentsEscrowMock();
        _horizonStaking = new HorizonStakingMock();
        PartialControllerMock.Entry[] memory entries = new PartialControllerMock.Entry[](2);
        entries[0] = PartialControllerMock.Entry({ name: "PaymentsEscrow", addr: address(_paymentsEscrow) });
        entries[1] = PartialControllerMock.Entry({ name: "Staking", addr: address(_horizonStaking) });
        _controller = address(new PartialControllerMock(entries));

        RecurringCollector implementation = new RecurringCollector(_controller, 1);
        _proxyAdminOwner = makeAddr("proxyAdminOwner");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            _proxyAdminOwner,
            abi.encodeCall(RecurringCollector.initialize, ("RecurringCollector", "1"))
        );
        _recurringCollector = RecurringCollector(address(proxy));
        _proxyAdminAddr = address(uint160(uint256(vm.load(address(proxy), ERC1967Utils.ADMIN_SLOT))));
        _recurringCollectorHelper = new RecurringCollectorHelper(_recurringCollector, _proxyAdminAddr);
    }

    /* solhint-disable graph/func-name-mixedcase */

    /// @notice Verify that initialize cannot be called twice
    function test_Upgrade_InitializeRevertsOnSecondCall() public {
        vm.expectRevert();
        _recurringCollector.initialize("RecurringCollector", "1");
    }

    /// @notice Deploy v1, create state (agreement + pause guardian), upgrade to v2, verify state persists
    function test_Upgrade_StatePreservedAfterUpgrade() public {
        // --- v1: create state ---

        // Set up a pause guardian
        vm.prank(address(0)); // governor is address(0) in mock controller
        _recurringCollector.setPauseGuardian(makeAddr("guardian"), true);

        // Accept an agreement via signed path
        uint256 signerKey = boundKey(12345);
        address payer = vm.addr(signerKey);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: payer,
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );
        _recurringCollectorHelper.authorizeSignerWithChecks(payer, signerKey);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, signerKey);

        _horizonStaking.setProvision(
            rca.serviceProvider,
            rca.dataService,
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
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, signature);

        // Capture v1 state
        IRecurringCollector.AgreementData memory v1Agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(uint8(v1Agreement.state), uint8(IRecurringCollector.AgreementState.Accepted));
        assertTrue(_recurringCollector.pauseGuardians(makeAddr("guardian")));

        // --- Upgrade to v2 (same implementation, simulates upgrade) ---

        RecurringCollector v2Implementation = new RecurringCollector(_controller, 1);
        vm.prank(_proxyAdminOwner);
        ProxyAdmin(_proxyAdminAddr).upgradeAndCall(
            ITransparentUpgradeableProxy(address(_recurringCollector)),
            address(v2Implementation),
            ""
        );

        // --- Verify state persisted ---

        IRecurringCollector.AgreementData memory v2Agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(uint8(v2Agreement.state), uint8(IRecurringCollector.AgreementState.Accepted), "agreement state lost");
        assertEq(v2Agreement.payer, payer, "payer lost");
        assertEq(v2Agreement.serviceProvider, rca.serviceProvider, "serviceProvider lost");
        assertEq(v2Agreement.dataService, rca.dataService, "dataService lost");
        assertEq(v2Agreement.activeTermsHash, _recurringCollector.hashRCA(rca), "terms hash lost");
        assertTrue(_recurringCollector.pauseGuardians(makeAddr("guardian")), "pause guardian lost");
    }

    /// @notice Only the proxy admin owner can upgrade
    function test_Upgrade_RevertWhen_NotProxyAdminOwner() public {
        RecurringCollector v2Implementation = new RecurringCollector(_controller, 1);

        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        ProxyAdmin(_proxyAdminAddr).upgradeAndCall(
            ITransparentUpgradeableProxy(address(_recurringCollector)),
            address(v2Implementation),
            ""
        );
    }

    /* solhint-enable graph/func-name-mixedcase */
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";
import { GraphPayments } from "@graphprotocol/horizon/contracts/payments/GraphPayments.sol";
import { GraphProxy } from "@graphprotocol/contracts/contracts/upgrades/GraphProxy.sol";
import { GraphProxyAdmin } from "@graphprotocol/contracts/contracts/upgrades/GraphProxyAdmin.sol";
import { HorizonStaking } from "@graphprotocol/horizon/contracts/staking/HorizonStaking.sol";
import { HorizonStakingExtension } from "@graphprotocol/horizon/contracts/staking/HorizonStakingExtension.sol";
import { IHorizonStaking } from "@graphprotocol/interfaces/contracts/horizon/IHorizonStaking.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { GraphTallyCollector } from "@graphprotocol/horizon/contracts/payments/collectors/GraphTallyCollector.sol";
import { RecurringCollector } from "@graphprotocol/horizon/contracts/payments/collectors/RecurringCollector.sol";
import { PaymentsEscrow } from "@graphprotocol/horizon/contracts/payments/PaymentsEscrow.sol";
import { UnsafeUpgrades } from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

import { Constants } from "./utils/Constants.sol";
import { DisputeManager } from "../../contracts/DisputeManager.sol";
import { SubgraphService } from "../../contracts/SubgraphService.sol";
import { Users } from "./utils/Users.sol";
import { Utils } from "./utils/Utils.sol";

import { MockCuration } from "./mocks/MockCuration.sol";
import { MockGRTToken } from "./mocks/MockGRTToken.sol";
import { MockRewardsManager } from "./mocks/MockRewardsManager.sol";
import { MockEpochManager } from "./mocks/MockEpochManager.sol";

abstract contract SubgraphBaseTest is Utils, Constants {
    /*
     * VARIABLES
     */

    /* Contracts */

    GraphProxyAdmin proxyAdmin;
    Controller controller;
    SubgraphService subgraphService;
    DisputeManager disputeManager;
    IHorizonStaking staking;
    GraphPayments graphPayments;
    IPaymentsEscrow escrow;
    GraphTallyCollector graphTallyCollector;
    RecurringCollector recurringCollector;

    HorizonStaking private stakingBase;
    HorizonStakingExtension private stakingExtension;

    MockCuration curation;
    MockGRTToken token;
    MockRewardsManager rewardsManager;
    MockEpochManager epochManager;

    /* Users */

    Users internal users;

    /*
     * SET UP
     */

    function setUp() public virtual {
        token = new MockGRTToken();

        // Setup Users
        users = Users({
            governor: createUser("governor"),
            deployer: createUser("deployer"),
            indexer: createUser("indexer"),
            operator: createUser("operator"),
            gateway: createUser("gateway"),
            verifier: createUser("verifier"),
            delegator: createUser("delegator"),
            arbitrator: createUser("arbitrator"),
            fisherman: createUser("fisherman"),
            rewardsDestination: createUser("rewardsDestination"),
            pauseGuardian: createUser("pauseGuardian")
        });

        deployProtocolContracts();
        setupProtocol();
        unpauseProtocol();
        vm.stopPrank();
    }

    function deployProtocolContracts() private {
        resetPrank(users.governor);
        proxyAdmin = new GraphProxyAdmin();
        controller = new Controller();

        resetPrank(users.deployer);
        GraphProxy stakingProxy = new GraphProxy(address(0), address(proxyAdmin));
        rewardsManager = new MockRewardsManager(token, REWARDS_PER_SIGNAL, REWARDS_PER_SUBGRAPH_ALLOCATION_UPDATE);
        curation = new MockCuration();
        epochManager = new MockEpochManager();

        // GraphPayments predict address
        bytes32 saltGraphPayments = keccak256("GraphPaymentsSalt");
        bytes32 paymentsHash = keccak256(
            bytes.concat(
                vm.getCode("GraphPayments.sol:GraphPayments"),
                abi.encode(address(controller), PROTOCOL_PAYMENT_CUT)
            )
        );
        address predictedGraphPaymentsAddress = vm.computeCreate2Address(
            saltGraphPayments,
            paymentsHash,
            users.deployer
        );

        // GraphEscrow predict address
        bytes32 saltEscrow = keccak256("GraphEscrowSalt");
        bytes32 escrowHash = keccak256(
            bytes.concat(
                vm.getCode("PaymentsEscrow.sol:PaymentsEscrow"),
                abi.encode(address(controller), WITHDRAW_ESCROW_THAWING_PERIOD)
            )
        );
        address predictedEscrowAddress = vm.computeCreate2Address(saltEscrow, escrowHash, users.deployer);

        resetPrank(users.governor);
        controller.setContractProxy(keccak256("GraphToken"), address(token));
        controller.setContractProxy(keccak256("Staking"), address(stakingProxy));
        controller.setContractProxy(keccak256("RewardsManager"), address(rewardsManager));
        controller.setContractProxy(keccak256("GraphPayments"), predictedGraphPaymentsAddress);
        controller.setContractProxy(keccak256("PaymentsEscrow"), predictedEscrowAddress);
        controller.setContractProxy(keccak256("EpochManager"), address(epochManager));
        controller.setContractProxy(keccak256("GraphTokenGateway"), makeAddr("GraphTokenGateway"));
        controller.setContractProxy(keccak256("GraphProxyAdmin"), makeAddr("GraphProxyAdmin"));
        controller.setContractProxy(keccak256("Curation"), address(curation));

        resetPrank(users.deployer);
        address disputeManagerImplementation = address(new DisputeManager(address(controller)));
        address disputeManagerProxy = UnsafeUpgrades.deployTransparentProxy(
            disputeManagerImplementation,
            users.governor,
            abi.encodeCall(
                DisputeManager.initialize,
                (
                    users.deployer,
                    users.arbitrator,
                    DISPUTE_PERIOD,
                    DISPUTE_DEPOSIT,
                    FISHERMAN_REWARD_PERCENTAGE,
                    MAX_SLASHING_PERCENTAGE
                )
            )
        );
        disputeManager = DisputeManager(disputeManagerProxy);
        disputeManager.transferOwnership(users.governor);

        graphTallyCollector = new GraphTallyCollector(
            "GraphTallyCollector",
            "1",
            address(controller),
            REVOKE_SIGNER_THAWING_PERIOD
        );
        recurringCollector = new RecurringCollector(
            "RecurringCollector",
            "1",
            address(controller),
            revokeSignerThawingPeriod
        );

        address subgraphServiceImplementation = address(
            new SubgraphService(
                address(controller),
                address(disputeManager),
                address(graphTallyCollector),
                address(curation),
                address(recurringCollector)
            )
        );
        address subgraphServiceProxy = UnsafeUpgrades.deployTransparentProxy(
            subgraphServiceImplementation,
            users.governor,
            abi.encodeCall(
                SubgraphService.initialize,
                (users.deployer, MINIMUM_PROVISION_TOKENS, DELEGATION_RATIO, STAKE_TO_FEES_RATIO)
            )
        );
        subgraphService = SubgraphService(subgraphServiceProxy);

        stakingExtension = new HorizonStakingExtension(address(controller), address(subgraphService));
        stakingBase = new HorizonStaking(address(controller), address(stakingExtension), address(subgraphService));

        graphPayments = new GraphPayments{ salt: saltGraphPayments }(address(controller), PROTOCOL_PAYMENT_CUT);
        escrow = new PaymentsEscrow{ salt: saltEscrow }(address(controller), WITHDRAW_ESCROW_THAWING_PERIOD);

        resetPrank(users.governor);
        disputeManager.setSubgraphService(address(subgraphService));
        proxyAdmin.upgrade(stakingProxy, address(stakingBase));
        proxyAdmin.acceptProxy(stakingBase, stakingProxy);
        staking = IHorizonStaking(address(stakingProxy));
    }

    function setupProtocol() private {
        resetPrank(users.deployer);
        subgraphService.transferOwnership(users.governor);
        resetPrank(users.governor);
        staking.setMaxThawingPeriod(MAX_WAIT_PERIOD);
        epochManager.setEpochLength(EPOCH_LENGTH);
        subgraphService.setMaxPOIStaleness(MAX_POI_STALENESS);
        subgraphService.setCurationCut(CURATION_CUT);
        subgraphService.setPauseGuardian(users.pauseGuardian, true);
    }

    function unpauseProtocol() private {
        resetPrank(users.governor);
        controller.setPaused(false);
    }

    function createUser(string memory name) internal returns (address) {
        address user = makeAddr(name);
        vm.deal({ account: user, newBalance: 100 ether });
        deal({ token: address(token), to: user, give: 10_000_000_000 ether });
        vm.label({ account: user, newLabel: name });
        return user;
    }

    function mint(address _address, uint256 amount) internal {
        deal({ token: address(token), to: _address, give: amount });
    }

    function burn(address _from, uint256 amount) internal {
        token.burnFrom(_from, amount);
    }
}

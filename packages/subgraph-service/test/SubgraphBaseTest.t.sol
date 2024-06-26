// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";
import { GraphPayments } from "@graphprotocol/horizon/contracts/payments/GraphPayments.sol";
import { GraphProxy } from "@graphprotocol/contracts/contracts/upgrades/GraphProxy.sol";
import { GraphProxyAdmin } from "@graphprotocol/contracts/contracts/upgrades/GraphProxyAdmin.sol";
import { HorizonStaking } from "@graphprotocol/horizon/contracts/staking/HorizonStaking.sol";
import { HorizonStakingExtension } from "@graphprotocol/horizon/contracts/staking/HorizonStakingExtension.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IHorizonStaking } from "@graphprotocol/horizon/contracts/interfaces/IHorizonStaking.sol";
import { IPaymentsEscrow } from "@graphprotocol/horizon/contracts/interfaces/IPaymentsEscrow.sol";
import { ITAPCollector } from "@graphprotocol/horizon/contracts/interfaces/ITAPCollector.sol";
import { TAPCollector } from "@graphprotocol/horizon/contracts/payments/collectors/TAPCollector.sol";
import { PaymentsEscrow } from "@graphprotocol/horizon/contracts/payments/PaymentsEscrow.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { Constants } from "./utils/Constants.sol";
import { DisputeManager } from "../contracts/DisputeManager.sol";
import { SubgraphService } from "../contracts/SubgraphService.sol";
import { Users } from "./utils/Users.sol";
import { Utils } from "./utils/Utils.sol";

import { MockGRTToken } from "./mocks/MockGRTToken.sol";
import { MockRewardsManager } from "./mocks/MockRewardsManager.sol";

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
    IGraphPayments graphPayments;
    IPaymentsEscrow escrow;
    ITAPCollector tapCollector;

    HorizonStaking private stakingBase;
    HorizonStakingExtension private stakingExtension;

    MockGRTToken token;
    MockRewardsManager rewardsManager;

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
            rewardsDestination: createUser("rewardsDestination")
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
        rewardsManager = new MockRewardsManager();

        // GraphPayments predict address
        bytes32 saltGraphPayments = keccak256("GraphPaymentsSalt");
        bytes32 paymentsHash = keccak256(bytes.concat(
            vm.getCode("GraphPayments.sol:GraphPayments"),
            abi.encode(address(controller), protocolPaymentCut)
        ));
        address predictedGraphPaymentsAddress = vm.computeCreate2Address(
            saltGraphPayments,
            paymentsHash,
            users.deployer
        );
        
        // GraphEscrow predict address
        bytes32 saltEscrow = keccak256("GraphEscrowSalt");
        bytes32 escrowHash = keccak256(bytes.concat(
            vm.getCode("PaymentsEscrow.sol:PaymentsEscrow"),
            abi.encode(
                address(controller),
                revokeCollectorThawingPeriod,
                withdrawEscrowThawingPeriod
            )
        ));
        address predictedEscrowAddress = vm.computeCreate2Address(
            saltEscrow,
            escrowHash,
            users.deployer
        );

        resetPrank(users.governor);
        controller.setContractProxy(keccak256("GraphToken"), address(token));
        controller.setContractProxy(keccak256("Staking"), address(stakingProxy));
        controller.setContractProxy(keccak256("RewardsManager"), address(rewardsManager));
        controller.setContractProxy(keccak256("GraphPayments"), predictedGraphPaymentsAddress);
        controller.setContractProxy(keccak256("PaymentsEscrow"), predictedEscrowAddress);
        controller.setContractProxy(keccak256("EpochManager"), makeAddr("EpochManager"));
        controller.setContractProxy(keccak256("GraphTokenGateway"), makeAddr("GraphTokenGateway"));
        controller.setContractProxy(keccak256("GraphProxyAdmin"), makeAddr("GraphProxyAdmin"));
        controller.setContractProxy(keccak256("Curation"), makeAddr("Curation"));

        resetPrank(users.deployer);
        address disputeManagerImplementation = address(new DisputeManager(address(controller)));
        address disputeManagerProxy = UnsafeUpgrades.deployTransparentProxy(
            disputeManagerImplementation,
            users.governor,
            abi.encodeCall(
                DisputeManager.initialize,
                (users.arbitrator, disputePeriod, minimumDeposit, fishermanRewardPercentage, maxSlashingPercentage)
            )
        );
        disputeManager = DisputeManager(disputeManagerProxy);

        tapCollector = new TAPCollector("TAPCollector", "1", address(controller));
        address curation = address(0xE4);
        address subgraphServiceImplementation = address(
            new SubgraphService(address(controller), address(disputeManager), address(tapCollector), curation)
        );
        address subgraphServiceProxy = UnsafeUpgrades.deployTransparentProxy(
            subgraphServiceImplementation,
            users.governor,
            abi.encodeCall(SubgraphService.initialize, (minimumProvisionTokens, delegationRatio))
        );
        subgraphService = SubgraphService(subgraphServiceProxy);

        disputeManager.setSubgraphService(address(subgraphService));

        stakingExtension = new HorizonStakingExtension(
            address(controller),
            address(subgraphService)
        );
        stakingBase = new HorizonStaking(
            address(controller),
            address(stakingExtension),
            address(subgraphService)
        );

        graphPayments = new GraphPayments{salt: saltGraphPayments}(
            address(controller), 
            protocolPaymentCut
        );
        escrow = new PaymentsEscrow{salt: saltEscrow}(
            address(controller),
            revokeCollectorThawingPeriod,
            withdrawEscrowThawingPeriod
        );

        resetPrank(users.governor);
        proxyAdmin.upgrade(stakingProxy, address(stakingBase));
        proxyAdmin.acceptProxy(stakingBase, stakingProxy);
        staking = IHorizonStaking(address(stakingProxy));
    }

    function setupProtocol() private {
        resetPrank(users.governor);
        staking.setMaxThawingPeriod(MAX_THAWING_PERIOD);
    }

    function unpauseProtocol() private {
        resetPrank(users.governor);
        controller.setPaused(false);
    }

    function createUser(string memory name) private returns (address) {
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
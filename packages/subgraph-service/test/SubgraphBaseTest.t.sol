// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { SubgraphService } from "../contracts/SubgraphService.sol";
import { DisputeManager } from "../contracts/DisputeManager.sol";
import { Users } from "./utils/Users.sol";
import { Constants } from "./utils/Constants.sol";
import { Utils } from "./utils/Utils.sol";

import { MockGRTToken } from "./mocks/MockGRTToken.sol";
import { MockHorizonStaking } from "./mocks/MockHorizonStaking.sol";
import { MockRewardsManager } from "./mocks/MockRewardsManager.sol";

abstract contract SubgraphBaseTest is Utils, Constants {

    /*
     * VARIABLES
     */

    /* Contracts */

    Controller controller;
    SubgraphService subgraphService;
    DisputeManager disputeManager;

    MockGRTToken token;
    MockHorizonStaking staking;
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
        vm.stopPrank();
    }

    function deployProtocolContracts() private {
        resetPrank(users.deployer);
        staking = new MockHorizonStaking(address(token));
        rewardsManager = new MockRewardsManager();

        address tapVerifier = address(0xE3);
        address curation = address(0xE4);

        resetPrank(users.governor);
        controller = new Controller();
        controller.setContractProxy(keccak256("GraphToken"), address(token));
        controller.setContractProxy(keccak256("Staking"), address(staking));
        controller.setContractProxy(keccak256("RewardsManager"), address(rewardsManager));
        controller.setContractProxy(keccak256("GraphPayments"), makeAddr("GraphPayments"));
        controller.setContractProxy(keccak256("PaymentsEscrow"), makeAddr("PaymentsEscrow"));
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

        address subgraphServiceImplementation = address(
            new SubgraphService(address(controller), address(disputeManager), tapVerifier, curation)
        );
        address subgraphServiceProxy = UnsafeUpgrades.deployTransparentProxy(
            subgraphServiceImplementation,
            users.governor,
            abi.encodeCall(SubgraphService.initialize, (minimumProvisionTokens, delegationRatio))
        );
        subgraphService = SubgraphService(subgraphServiceProxy);

        disputeManager.setSubgraphService(address(subgraphService));
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
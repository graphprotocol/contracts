// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { GraphProxyAdmin } from "@graphprotocol/contracts/contracts/upgrades/GraphProxyAdmin.sol";
import { GraphProxy } from "@graphprotocol/contracts/contracts/upgrades/GraphProxy.sol";
import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { PaymentsEscrow } from "contracts/payments/PaymentsEscrow.sol";
import { GraphPayments } from "contracts/payments/GraphPayments.sol";
import { GraphTallyCollector } from "contracts/payments/collectors/GraphTallyCollector.sol";
import { IHorizonStaking } from "contracts/interfaces/IHorizonStaking.sol";
import { HorizonStaking } from "contracts/staking/HorizonStaking.sol";
import { HorizonStakingExtension } from "contracts/staking/HorizonStakingExtension.sol";
import { IHorizonStakingTypes } from "contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { MockGRTToken } from "../contracts/mocks/MockGRTToken.sol";
import { EpochManagerMock } from "../contracts/mocks/EpochManagerMock.sol";
import { RewardsManagerMock } from "../contracts/mocks/RewardsManagerMock.sol";
import { CurationMock } from "../contracts/mocks/CurationMock.sol";
import { Constants } from "./utils/Constants.sol";
import { Users } from "./utils/Users.sol";
import { Utils } from "./utils/Utils.sol";

abstract contract GraphBaseTest is IHorizonStakingTypes, Utils, Constants {
    /*
     * VARIABLES
     */

    /* Contracts */

    GraphProxyAdmin public proxyAdmin;
    Controller public controller;
    MockGRTToken public token;
    GraphPayments public payments;
    PaymentsEscrow public escrow;
    IHorizonStaking public staking;
    EpochManagerMock public epochManager;
    RewardsManagerMock public rewardsManager;
    CurationMock public curation;
    GraphTallyCollector graphTallyCollector;

    HorizonStaking private stakingBase;
    HorizonStakingExtension private stakingExtension;

    address subgraphDataServiceLegacyAddress = makeAddr("subgraphDataServiceLegacyAddress");
    address subgraphDataServiceAddress = makeAddr("subgraphDataServiceAddress");

    address graphTokenGatewayAddress = makeAddr("GraphTokenGateway");

    /* Users */

    Users internal users;

    /*
     * SET UP
     */

    function setUp() public virtual {
        // Deploy ERC20 token
        vm.prank(users.deployer);
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
            legacySlasher: createUser("legacySlasher")
        });

        // Deploy protocol contracts
        deployProtocolContracts();
        setupProtocol();
        unpauseProtocol();

        // Label contracts
        vm.label({ account: address(controller), newLabel: "Controller" });
        vm.label({ account: address(token), newLabel: "GraphToken" });
        vm.label({ account: address(payments), newLabel: "GraphPayments" });
        vm.label({ account: address(escrow), newLabel: "PaymentsEscrow" });
        vm.label({ account: address(staking), newLabel: "HorizonStaking" });
        vm.label({ account: address(stakingExtension), newLabel: "HorizonStakingExtension" });
        vm.label({ account: address(graphTallyCollector), newLabel: "GraphTallyCollector" });

        // Ensure caller is back to the original msg.sender
        vm.stopPrank();
    }

    function deployProtocolContracts() private {
        vm.startPrank(users.governor);
        proxyAdmin = new GraphProxyAdmin();
        controller = new Controller();

        // Staking Proxy
        resetPrank(users.deployer);
        GraphProxy stakingProxy = new GraphProxy(address(0), address(proxyAdmin));

        // GraphPayments predict address
        bytes memory paymentsImplementationParameters = abi.encode(address(controller), protocolPaymentCut);
        bytes memory paymentsImplementationBytecode = abi.encodePacked(
            type(GraphPayments).creationCode,
            paymentsImplementationParameters
        );
        address predictedPaymentsImplementationAddress = _computeAddress(
            "GraphPayments",
            paymentsImplementationBytecode,
            users.deployer
        );

        bytes memory paymentsProxyParameters = abi.encode(
            predictedPaymentsImplementationAddress,
            users.governor,
            abi.encodeCall(GraphPayments.initialize, ())
        );
        bytes memory paymentsProxyBytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            paymentsProxyParameters
        );
        address predictedPaymentsProxyAddress = _computeAddress(
            "TransparentUpgradeableProxy",
            paymentsProxyBytecode,
            users.deployer
        );

        // PaymentsEscrow
        bytes memory escrowImplementationParameters = abi.encode(address(controller), withdrawEscrowThawingPeriod);
        bytes memory escrowImplementationBytecode = abi.encodePacked(
            type(PaymentsEscrow).creationCode,
            escrowImplementationParameters
        );
        address predictedEscrowImplementationAddress = _computeAddress(
            "PaymentsEscrow",
            escrowImplementationBytecode,
            users.deployer
        );

        bytes memory escrowProxyParameters = abi.encode(
            predictedEscrowImplementationAddress,
            users.governor,
            abi.encodeCall(PaymentsEscrow.initialize, ())
        );
        bytes memory escrowProxyBytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            escrowProxyParameters
        );
        address predictedEscrowProxyAddress = _computeAddress(
            "TransparentUpgradeableProxy",
            escrowProxyBytecode,
            users.deployer
        );

        // Epoch Manager
        epochManager = new EpochManagerMock();

        // Rewards Manager
        rewardsManager = new RewardsManagerMock(token, ALLOCATIONS_REWARD_CUT);

        // Curation
        curation = new CurationMock();

        // Setup controller
        resetPrank(users.governor);
        controller.setContractProxy(keccak256("GraphToken"), address(token));
        controller.setContractProxy(keccak256("PaymentsEscrow"), predictedEscrowProxyAddress);
        controller.setContractProxy(keccak256("GraphPayments"), predictedPaymentsProxyAddress);
        controller.setContractProxy(keccak256("Staking"), address(stakingProxy));
        controller.setContractProxy(keccak256("EpochManager"), address(epochManager));
        controller.setContractProxy(keccak256("RewardsManager"), address(rewardsManager));
        controller.setContractProxy(keccak256("Curation"), address(curation));
        controller.setContractProxy(keccak256("GraphTokenGateway"), graphTokenGatewayAddress);
        controller.setContractProxy(keccak256("GraphProxyAdmin"), address(proxyAdmin));

        resetPrank(users.deployer);
        {
            address paymentsImplementationAddress = _deployContract("GraphPayments", paymentsImplementationBytecode);
            address paymentsProxyAddress = _deployContract("TransparentUpgradeableProxy", paymentsProxyBytecode);
            assertEq(paymentsImplementationAddress, predictedPaymentsImplementationAddress);
            assertEq(paymentsProxyAddress, predictedPaymentsProxyAddress);
            payments = GraphPayments(paymentsProxyAddress);
        }

        {
            address escrowImplementationAddress = _deployContract("PaymentsEscrow", escrowImplementationBytecode);
            address escrowProxyAddress = _deployContract("TransparentUpgradeableProxy", escrowProxyBytecode);
            assertEq(escrowImplementationAddress, predictedEscrowImplementationAddress);
            assertEq(escrowProxyAddress, predictedEscrowProxyAddress);
            escrow = PaymentsEscrow(escrowProxyAddress);
        }

        stakingExtension = new HorizonStakingExtension(address(controller), subgraphDataServiceLegacyAddress);
        stakingBase = new HorizonStaking(
            address(controller),
            address(stakingExtension),
            subgraphDataServiceLegacyAddress
        );

        graphTallyCollector = new GraphTallyCollector("GraphTallyCollector", "1", address(controller), revokeSignerThawingPeriod);

        resetPrank(users.governor);
        proxyAdmin.upgrade(stakingProxy, address(stakingBase));
        proxyAdmin.acceptProxy(stakingBase, stakingProxy);
        staking = IHorizonStaking(address(stakingProxy));
    }

    function setupProtocol() private {
        resetPrank(users.governor);
        staking.setMaxThawingPeriod(MAX_THAWING_PERIOD);
        epochManager.setEpochLength(EPOCH_LENGTH);
    }

    function unpauseProtocol() private {
        resetPrank(users.governor);
        controller.setPaused(false);
    }

    function createUser(string memory name) internal returns (address) {
        address user = makeAddr(name);
        vm.deal({ account: user, newBalance: 100 ether });
        deal({ token: address(token), to: user, give: type(uint256).max });
        vm.label({ account: user, newLabel: name });
        return user;
    }

    /*
     * TOKEN HELPERS
     */

    function mint(address _address, uint256 amount) internal {
        deal({ token: address(token), to: _address, give: amount });
    }

    function approve(address spender, uint256 amount) internal {
        token.approve(spender, amount);
    }

    /*
     * PRIVATE
     */

    function _computeAddress(
        string memory contractName,
        bytes memory bytecode,
        address deployer
    ) private pure returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(contractName, "Salt"));
        return Create2.computeAddress(salt, keccak256(bytecode), deployer);
    }

    function _deployContract(string memory contractName, bytes memory bytecode) private returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(contractName, "Salt"));
        return Create2.deploy(0, salt, bytecode);
    }
}

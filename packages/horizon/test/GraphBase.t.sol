// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphProxyAdmin } from "@graphprotocol/contracts/contracts/upgrades/GraphProxyAdmin.sol";
import { GraphProxy } from "@graphprotocol/contracts/contracts/upgrades/GraphProxy.sol";
import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";

import { PaymentsEscrow } from "contracts/payments/PaymentsEscrow.sol";
import { GraphPayments } from "contracts/payments/GraphPayments.sol";
import { IHorizonStaking } from "contracts/interfaces/IHorizonStaking.sol";
import { HorizonStaking } from "contracts/staking/HorizonStaking.sol";
import { HorizonStakingExtension } from "contracts/staking/HorizonStakingExtension.sol";
import { MockGRTToken } from "../contracts/mocks/MockGRTToken.sol";
import { EpochManagerMock } from "../contracts/mocks/EpochManagerMock.sol";
import { RewardsManagerMock } from "../contracts/mocks/RewardsManagerMock.sol";
import { CurationMock } from "../contracts/mocks/CurationMock.sol";
import { Constants } from "./utils/Constants.sol";
import { Users } from "./utils/Users.sol";
import { Utils } from "./utils/Utils.sol";

abstract contract GraphBaseTest is Utils, Constants {

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
    
    HorizonStaking private stakingBase;
    HorizonStakingExtension private stakingExtension;

    address subgraphDataServiceLegacyAddress = makeAddr("subgraphDataServiceLegacyAddress");
    address subgraphDataServiceAddress = makeAddr("subgraphDataServiceAddress");

    /* Users */

    Users internal users;

    /* Constants */

    Constants public constants;

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
            delegator: createUser("delegator")
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
    }

    function deployProtocolContracts() private {
        vm.startPrank(users.governor);
        proxyAdmin = new GraphProxyAdmin();
        controller = new Controller();

        // Staking Proxy
        resetPrank(users.deployer);
        GraphProxy stakingProxy = new GraphProxy(address(0), address(proxyAdmin));

        // GraphPayments predict address
        bytes32 saltPayments = keccak256("GraphPaymentsSalt");
        bytes32 paymentsHash = keccak256(bytes.concat(
            vm.getCode("GraphPayments.sol:GraphPayments"),
            abi.encode(address(controller), protocolPaymentCut)
        ));
        address predictedPaymentsAddress = vm.computeCreate2Address(
            saltPayments,
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
        address predictedAddressEscrow = vm.computeCreate2Address(
            saltEscrow,
            escrowHash,
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
        controller.setContractProxy(keccak256("PaymentsEscrow"), predictedAddressEscrow);
        controller.setContractProxy(keccak256("GraphPayments"), predictedPaymentsAddress);
        controller.setContractProxy(keccak256("Staking"), address(stakingProxy));
        controller.setContractProxy(keccak256("EpochManager"), address(epochManager));
        controller.setContractProxy(keccak256("RewardsManager"), address(rewardsManager));
        controller.setContractProxy(keccak256("Curation"), address(curation));
        controller.setContractProxy(keccak256("GraphTokenGateway"), makeAddr("GraphTokenGateway"));
        controller.setContractProxy(keccak256("GraphProxyAdmin"), address(proxyAdmin));
        
        resetPrank(users.deployer);
        payments = new GraphPayments{salt: saltPayments}(
            address(controller), 
            protocolPaymentCut
        );
        escrow = new PaymentsEscrow{salt: saltEscrow}(
            address(controller),
            revokeCollectorThawingPeriod,
            withdrawEscrowThawingPeriod
        );
        stakingExtension = new HorizonStakingExtension(
            address(controller),
            subgraphDataServiceLegacyAddress
        );
        stakingBase = new HorizonStaking(
            address(controller),
            address(stakingExtension),
            subgraphDataServiceLegacyAddress
        );

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
}
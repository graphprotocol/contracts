// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";

import { GraphEscrow } from "contracts/escrow/GraphEscrow.sol";
import { GraphPayments } from "contracts/payments/GraphPayments.sol";
import { IHorizonStaking } from "contracts/IHorizonStaking.sol";
import { HorizonStaking } from "contracts/HorizonStaking.sol";
import { HorizonStakingExtension } from "contracts/HorizonStakingExtension.sol";
import { MockGRTToken } from "../contracts/mocks/MockGRTToken.sol";
import { Constants } from "./utils/Constants.sol";
import { Users } from "./utils/Users.sol";

abstract contract GraphBaseTest is Test, Constants {

    /* Contracts */

    Controller public controller;
    MockGRTToken public token;
    GraphPayments public payments;
    GraphEscrow public escrow;
    IHorizonStaking public staking;
    
    HorizonStaking private stakingBase;
    HorizonStakingExtension private stakingExtension;

    address subgraphDataServiceAddress = makeAddr("subgraphDataServiceAddress");
    address exponentialRebates = makeAddr("exponentialRebates");

    /* Users */

    Users internal users;

    /* Constants */

    Constants public constants;

    /* Set Up */

    function setUp() public virtual {
        // Deploy ERC20 token
        token = new MockGRTToken();

        // Setup Users
        users = Users({
            governor: createUser("governor"),
            deployer: createUser("deployer"),
            indexer: createUser("indexer"),
            operator: createUser("operator"),
            gateway: createUser("gateway"),
            verifier: createUser("verifier")
        });

        // Deploy protocol contracts
        deployProtocolContracts();
        unpauseProtocol();
    }

    function deployProtocolContracts() private {
        vm.prank(users.governor);
        controller = new Controller();

        // GraphPayments preddict address
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
        
        // GraphEscrow preddict address
        bytes32 saltEscrow = keccak256("GraphEscrowSalt");
        bytes32 escrowHash = keccak256(bytes.concat(
            vm.getCode("GraphEscrow.sol:GraphEscrow"),
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

        // HorizonStakingExtension preddict address
        bytes32 saltHorizonStakingExtension = keccak256("HorizonStakingExtensionSalt");
        bytes32 horizonStakingExtensionHash = keccak256(bytes.concat(
            vm.getCode("HorizonStakingExtension.sol:HorizonStakingExtension"),
            abi.encode(address(controller), subgraphDataServiceAddress, exponentialRebates)
        ));
        address predictedAddressHorizonStakingExtension = vm.computeCreate2Address(
            saltHorizonStakingExtension,
            horizonStakingExtensionHash,
            users.deployer
        );

        // HorizonStaking preddict address
        bytes32 saltHorizonStaking = keccak256("saltHorizonStaking");
        bytes32 horizonStakingHash = keccak256(bytes.concat(
            vm.getCode("HorizonStaking.sol:HorizonStaking"),
            abi.encode(
                address(controller), 
                predictedAddressHorizonStakingExtension, 
                subgraphDataServiceAddress
            )
        ));
        address predictedAddressHorizonStaking = vm.computeCreate2Address(
            saltHorizonStaking,
            horizonStakingHash,
            users.deployer
        );

        // Setup controller
        vm.startPrank(users.governor);
        controller.setContractProxy(keccak256("GraphToken"), address(token));
        controller.setContractProxy(keccak256("GraphEscrow"), predictedAddressEscrow);
        controller.setContractProxy(keccak256("GraphPayments"), predictedPaymentsAddress);
        controller.setContractProxy(keccak256("Staking"), predictedAddressHorizonStaking);
        vm.stopPrank();
        
        vm.startPrank(users.deployer);
        payments = new GraphPayments{salt: saltPayments}(
            address(controller), 
            protocolPaymentCut
        );
        escrow = new GraphEscrow{salt: saltEscrow}(
            address(controller),
            revokeCollectorThawingPeriod,
            withdrawEscrowThawingPeriod
        );
        stakingBase = new HorizonStaking{salt: saltHorizonStaking}(
            address(controller),
            predictedAddressHorizonStakingExtension,
            subgraphDataServiceAddress
        );
        staking = IHorizonStaking(address(stakingBase));
        stakingExtension = new HorizonStakingExtension{salt: saltHorizonStakingExtension}(
            address(controller),
            subgraphDataServiceAddress,
            exponentialRebates
        );
        vm.stopPrank();
    }

    function unpauseProtocol() private {
        vm.prank(users.governor);
        controller.setPaused(false);
    }

    function createUser(string memory name) private returns (address) {
        address user = makeAddr(name);
        deal({ token: address(token), to: user, give: 10000 ether });
        return user;
    }

    /* Token helpers */

    function mint(address _address, uint256 amount) internal {
        deal({ token: address(token), to: _address, give: amount });
    }

    function approve(address spender, uint256 amount) internal {
        token.approve(spender, amount);
    }
}
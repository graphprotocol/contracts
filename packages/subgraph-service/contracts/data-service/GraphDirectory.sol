// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IController } from "@graphprotocol/contracts/contracts/governance/IController.sol";
import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
// import { IGraphTokenGateway } from "@graphprotocol/contracts/contracts/gateway/IGraphTokenGateway.sol";
import { IEpochManager } from "@graphprotocol/contracts/contracts/epochs/IEpochManager.sol";
import { IRewardsManager } from "@graphprotocol/contracts/contracts/rewards/IRewardsManager.sol";
import { IGraphEscrow } from "../interfaces/IGraphEscrow.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

abstract contract GraphDirectory {
    IController public immutable GRAPH_CONTROLLER;
    IHorizonStaking public immutable GRAPH_STAKING;
    IEpochManager public immutable GRAPH_EPOCH_MANAGER;
    IGraphToken public immutable GRAPH_TOKEN;
    // IGraphTokenGateway public immutable graphTokenGateway;
    IGraphEscrow public immutable GRAPH_ESCROW;
    IGraphPayments public immutable GRAPH_PAYMENTS;
    IRewardsManager public immutable GRAPH_REWARDS_MANAGER;

    event GraphDirectoryInitialized(
        IController graphController,
        IHorizonStaking graphStaking,
        IEpochManager graphEpochManager,
        IGraphToken graphToken,
        // address graphTokenGateway,
        IGraphEscrow graphEscrow,
        IGraphPayments graphPayments,
        IRewardsManager graphRewardsManager
    );

    constructor(address _controller) {
        GRAPH_CONTROLLER = IController(_controller);
        GRAPH_STAKING = IHorizonStaking(GRAPH_CONTROLLER.getContractProxy(keccak256("Staking")));
        GRAPH_EPOCH_MANAGER = IEpochManager(GRAPH_CONTROLLER.getContractProxy(keccak256("EpochManager")));
        GRAPH_TOKEN = IGraphToken(GRAPH_CONTROLLER.getContractProxy(keccak256("GraphToken")));
        // graphTokenGateway = graphController.getContractProxy(keccak256("GraphTokenGateway"));
        GRAPH_ESCROW = IGraphEscrow(GRAPH_CONTROLLER.getContractProxy(keccak256("GraphEscrow")));
        GRAPH_PAYMENTS = IGraphPayments(GRAPH_CONTROLLER.getContractProxy(keccak256("GraphPayments")));
        GRAPH_REWARDS_MANAGER = IRewardsManager(GRAPH_CONTROLLER.getContractProxy(keccak256("RewardsManager")));
        emit GraphDirectoryInitialized(
            GRAPH_CONTROLLER,
            GRAPH_STAKING,
            GRAPH_EPOCH_MANAGER,
            GRAPH_TOKEN,
            // graphTokenGateway,
            GRAPH_ESCROW,
            GRAPH_PAYMENTS,
            GRAPH_REWARDS_MANAGER
        );
    }
}

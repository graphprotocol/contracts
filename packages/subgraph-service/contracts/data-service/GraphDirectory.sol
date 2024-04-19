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

contract GraphDirectory {
    IController public immutable graphController;
    IHorizonStaking public immutable graphStaking;
    IEpochManager public immutable graphEpochManager;
    IGraphToken public immutable graphToken;
    // IGraphTokenGateway public immutable graphTokenGateway;
    IGraphEscrow public immutable graphEscrow;
    IGraphPayments public immutable graphPayments;
    IRewardsManager public immutable graphRewardsManager;

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
        graphController = IController(_controller);
        graphStaking = IHorizonStaking(graphController.getContractProxy(keccak256("Staking")));
        graphEpochManager = IEpochManager(graphController.getContractProxy(keccak256("EpochManager")));
        graphToken = IGraphToken(graphController.getContractProxy(keccak256("GraphToken")));
        // graphTokenGateway = graphController.getContractProxy(keccak256("GraphTokenGateway"));
        graphEscrow = IGraphEscrow(graphController.getContractProxy(keccak256("GraphEscrow")));
        graphPayments = IGraphPayments(graphController.getContractProxy(keccak256("GraphPayments")));
        graphRewardsManager = IRewardsManager(graphController.getContractProxy(keccak256("RewardsManager")));
        emit GraphDirectoryInitialized(
            graphController,
            graphStaking,
            graphEpochManager,
            graphToken,
            // graphTokenGateway,
            graphEscrow,
            graphPayments,
            graphRewardsManager
        );
    }
}
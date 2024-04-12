// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.24;

import { IController } from "@graphprotocol/contracts/contracts/governance/IController.sol";
import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IGraphEscrow } from "./interfaces/IGraphEscrow.sol";
import { IGraphPayments } from "./interfaces/IGraphPayments.sol";

contract GraphDirectory {
    IController public immutable graphController;
    IHorizonStaking public immutable graphStaking;
    IGraphToken public immutable graphToken;
    IGraphEscrow public immutable graphEscrow;
    IGraphPayments public immutable graphPayments;

    constructor(address _controller) {
        graphController = IController(_controller);
        graphStaking = IHorizonStaking(graphController.getContractProxy(keccak256("Staking")));
        graphToken = IGraphToken(graphController.getContractProxy(keccak256("GraphToken")));
        graphEscrow = IGraphEscrow(graphController.getContractProxy(keccak256("GraphEscrow")));
        graphPayments = IGraphPayments(graphController.getContractProxy(keccak256("GraphPayments")));
    }
}

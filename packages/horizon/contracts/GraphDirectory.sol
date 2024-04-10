// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IController } from "@graphprotocol/contracts/contracts/governance/IController.sol";

contract GraphDirectory {
    address public immutable CONTROLLER;
    address public immutable STAKING;
    address public immutable EPOCH_MANAGER;
    address public immutable GRAPH_TOKEN;
    address public immutable GRAPH_TOKEN_GATEWAY;
    // TODO: also GraphPayments and ScalarEscrow?

    constructor(address _controller) {
        CONTROLLER = _controller;
        STAKING = IController(_controller).getContractProxy(keccak256("Staking"));
        EPOCH_MANAGER = IController(_controller).getContractProxy(keccak256("EpochManager"));
        GRAPH_TOKEN = IController(_controller).getContractProxy(keccak256("GraphToken"));
        GRAPH_TOKEN_GATEWAY = IController(_controller).getContractProxy(keccak256("GraphTokenGateway"));
    }
}

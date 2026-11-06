// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ICallhookReceiver } from "@graphprotocol/interfaces/contracts/contracts/gateway/ICallhookReceiver.sol";
import { IGraphTokenLike } from "../interfaces/IGraphTokenLike.sol";

/// Stands in for L2GraphTokenGateway: mints first, then forwards the callhook, like finalizeInboundTransfer
contract L2GatewayMock {
    address public immutable token;

    constructor(address token_) {
        token = token_;
    }

    function deliver(address gns, address l1From, uint256 amount, bytes calldata data) external {
        IGraphTokenLike(token).mint(gns, amount);
        ICallhookReceiver(gns).onTokenTransfer(l1From, amount, data);
    }
}

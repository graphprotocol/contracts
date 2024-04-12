// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

import { IGraphPayments } from "./interfaces/IGraphPayments.sol";
import { IGraphEscrow } from "./interfaces/IGraphEscrow.sol";
import { GraphPaymentsStorageV1Storage } from "./GraphPaymentsStorage.sol";

contract GraphEscrow is IGraphPayments, GraphPaymentsStorageV1Storage {
    // -- Errors --

    // -- Immutable variables --

    IGraphToken public immutable graphToken;
    IHorizonStaking public immutable staking;
    IGraphEscrow public immutable graphEscrow;

    // -- Modifier --

    // -- Constructor --

    constructor(address _graphToken, address _staking, address _graphEscrow) {
        graphToken = IGraphToken(_graphToken);
        staking = IHorizonStaking(_staking);
        graphEscrow = IGraphEscrow(_graphEscrow);
    }

    // approve a data service to collect funds
    function approveCollector(address dataService) external {}

    // thaw a data service's collector authorization
    function thawCollector(address dataService) external {}

    // cancel thawing a data service's collector authorization
    function cancelThawCollector(address dataService) external {}

    // revoke authorized collector
    function revokeCollector(address dataService) external {}

    // collect funds from a sender, pay cuts and forward the rest to the receiver
    function collect(
        address sender,
        address receiver,
        uint256 amount,
        uint256 paymentType,
        uint256 dataServiceCut
    ) external {}
}

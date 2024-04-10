// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";

import { IGraphPayments } from "./interfaces/IGraphPayments.sol";
import { GraphEscrowStorageV1Storage } from "./GraphEscrowStorage.sol";

contract GraphEscrow is GraphEscrowStorageV1Storage {
    // -- Errors --

    error GraphEscrowNotGraphPayments();

    // -- Immutable variables --

    IGraphToken public immutable graphToken;
    IGraphPayments public immutable graphPayments;

    // -- Modifier --

    modifier onlyGraphPayments() {
        if (msg.sender != address(graphPayments)) {
            revert GraphEscrowNotGraphPayments();
        }
        _;
    }

    // -- Constructor --

    constructor(address _graphToken, address _graphPayments, uint256 _withdrawEscrowThawingPeriod) {
        graphToken = IGraphToken(_graphToken);
        graphPayments = IGraphPayments(_graphPayments);
        _withdrawEscrowThawingPeriod = _withdrawEscrowThawingPeriod;
    }

    // Deposit funds into the escrow for a receiver
    function deposit(address receiver, uint256 amount) external {}

    // Deposit funds into the escrow for multiple receivers
    function depositMany(address[] calldata receivers, uint256[] calldata amounts) external {}

    // Requests to thaw a specific amount of escrow from a receiver's escrow account
    function thaw(address receiver, uint256 amount) external {}

    // Withdraws all thawed escrow from a receiver's escrow account
    function withdraw(address receiver) external {}

    // Collect from escrow (up to amount available in escrow) for a receiver using sender's deposit
    function collect(address sender, address receiver, uint256 amount) external onlyGraphPayments {}
}

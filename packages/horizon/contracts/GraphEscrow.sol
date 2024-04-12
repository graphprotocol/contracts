// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";

import { IGraphEscrow } from "./interfaces/IGraphEscrow.sol";
import { IGraphPayments } from "./interfaces/IGraphPayments.sol";
import { GraphDirectory } from "./GraphDirectory.sol";
import { GraphEscrowStorageV1Storage } from "./GraphEscrowStorage.sol";

contract GraphEscrow is IGraphEscrow, GraphEscrowStorageV1Storage, GraphDirectory {
    // -- Errors --

    error GraphEscrowNotGraphPayments();

    // -- Events --

    event Deposit(address indexed sender, address indexed receiver, uint256 amount);

    // -- Modifier --

    modifier onlyGraphPayments() {
        if (msg.sender != address(graphPayments)) {
            revert GraphEscrowNotGraphPayments();
        }
        _;
    }

    // -- Constructor --

    constructor(address _controller, uint256 _withdrawEscrowThawingPeriod) GraphDirectory(_controller) {
        withdrawEscrowThawingPeriod = _withdrawEscrowThawingPeriod;
    }

    // Deposit funds into the escrow for a receiver
    function deposit(address receiver, uint256 amount) external {
        escrowAccounts[msg.sender][receiver].balance += amount;
        graphToken.transferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, receiver, amount);
    }

    // Deposit funds into the escrow for multiple receivers
    function depositMany(address[] calldata receivers, uint256[] calldata amounts) external {}

    // Requests to thaw a specific amount of escrow from a receiver's escrow account
    function thaw(address receiver, uint256 amount) external {}

    // Withdraws all thawed escrow from a receiver's escrow account
    function withdraw(address receiver) external {}

    // Collect from escrow (up to amount available in escrow) for a receiver using sender's deposit
    function collect(address sender, address receiver, uint256 amount) external onlyGraphPayments {}
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IGraphPayments {
    function collect(address sender, address serviceProvider, uint256 tokens) external;
}

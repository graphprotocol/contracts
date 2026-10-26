// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IBridgeEscrowLike {
    function initialize(address controller) external;

    function approveAll(address spender) external;

    function revokeAll(address spender) external;
}

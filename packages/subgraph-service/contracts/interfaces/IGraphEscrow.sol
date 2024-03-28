// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IGraphEscrow {
    function getSender(address signer) external view returns (address sender);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphEscrow } from "./interfaces/IGraphEscrow.sol";

contract GraphEscrowStorageV1Storage {
    // Stores how much escrow each sender has deposited for each receiver, as well as thawing information
    mapping(address sender => mapping(address receiver => IGraphEscrow.EscrowAccount escrowAccount))
        public escrowAccounts;

    // The duration (in seconds) in which escrow funds are thawing before they can be withdrawn
    uint256 public immutable withdrawEscrowThawingPeriod;

    // The maximum thawing period (in seconds) for both escrow withdrawal and signer revocation
    // This is a precautionary measure to avoid inadvertedly locking funds for too long
    uint256 public constant MAX_THAWING_PERIOD = 90 days;
}

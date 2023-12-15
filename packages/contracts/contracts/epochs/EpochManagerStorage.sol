// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../governance/Managed.sol";

contract EpochManagerV1Storage is Managed {
    // -- State --

    // Epoch length in blocks
    uint256 public epochLength;

    // Epoch that was last run
    uint256 public lastRunEpoch;

    // Block and epoch when epoch length was last updated
    uint256 public lastLengthUpdateEpoch;
    uint256 public lastLengthUpdateBlock;
}

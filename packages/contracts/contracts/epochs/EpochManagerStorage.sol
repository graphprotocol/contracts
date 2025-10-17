// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { Managed } from "../governance/Managed.sol";

/**
 * @title Epoch Manager Storage V1
 * @author Edge & Node
 * @notice Storage contract for the Epoch Manager
 */
contract EpochManagerV1Storage is Managed {
    // -- State --

    /// @notice Epoch length in blocks
    uint256 public epochLength;

    /// @notice Epoch that was last run
    uint256 public lastRunEpoch;

    /// @notice Epoch when epoch length was last updated
    uint256 public lastLengthUpdateEpoch;
    /// @notice Block when epoch length was last updated
    uint256 public lastLengthUpdateBlock;
}

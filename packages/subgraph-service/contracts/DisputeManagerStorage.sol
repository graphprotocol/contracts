// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { IDisputeManager } from "./interfaces/IDisputeManager.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";

abstract contract DisputeManagerV1Storage {
    /// @notice The Subgraph Service contract address
    ISubgraphService public subgraphService;

    /// @notice The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    /// @notice dispute period in seconds
    uint64 public disputePeriod;

    /// @notice Minimum deposit required to create a Dispute
    uint256 public minimumDeposit;

    /// @notice Percentage of indexer slashed funds to assign as a reward to fisherman in successful dispute. In PPM.
    uint32 public fishermanRewardCut;

    /// @notice List of disputes created
    mapping(bytes32 disputeId => IDisputeManager.Dispute dispute) public disputes;
}

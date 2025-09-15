// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

/**
 * @title DisputeManagerStorage
 * @notice This contract holds all the storage variables for the Dispute Manager contract.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract DisputeManagerV1Storage {
    /// @notice The Subgraph Service contract address
    ISubgraphService public subgraphService;

    /// @notice The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    /// @notice dispute period in seconds
    uint64 public disputePeriod;

    /// @notice Deposit required to create a Dispute
    uint256 public disputeDeposit;

    /// @notice Percentage of indexer slashed funds to assign as a reward to fisherman in successful dispute. In PPM.
    uint32 public fishermanRewardCut;

    /// @notice Maximum percentage of indexer stake that can be slashed on a dispute. In PPM.
    uint32 public maxSlashingCut;

    /// @notice List of disputes created
    mapping(bytes32 disputeId => IDisputeManager.Dispute dispute) public disputes;
}

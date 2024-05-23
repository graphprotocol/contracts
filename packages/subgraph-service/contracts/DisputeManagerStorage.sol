// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IDisputeManager } from "./interfaces/IDisputeManager.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";

abstract contract DisputeManagerV1Storage {
    // -- State --

    ISubgraphService public subgraphService;

    // The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    // dispute period in seconds
    uint64 public disputePeriod;

    // Minimum deposit required to create a Dispute
    uint256 public minimumDeposit;

    // Percentage of indexer slashed funds to assign as a reward to fisherman in successful dispute
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public fishermanRewardCut;

    // Maximum percentage of indexer stake that can be slashed on a dispute
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public maxSlashingCut;

    // Disputes created : disputeID => Dispute
    // disputeID - check creation functions to see how disputeID is built
    mapping(bytes32 disputeID => IDisputeManager.Dispute dispute) public disputes;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "../governance/Managed.sol";

import "./IDisputeManager.sol";

contract DisputeManagerV1Storage is Managed {
    // -- State --

    bytes32 internal DOMAIN_SEPARATOR;

    // The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    // Minimum deposit required to create a Dispute
    uint256 public minimumDeposit;

    // Percentage of indexer slashed funds to assign as a reward to fisherman in successful dispute
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public fishermanRewardPercentage;

    // Percentage of indexer stake to slash on disputes
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public slashingPercentage;

    // Disputes created : disputeID => Dispute
    // disputeID - check creation functions to see how disputeID is built
    mapping(bytes32 => IDisputeManager.Dispute) public disputes;
}

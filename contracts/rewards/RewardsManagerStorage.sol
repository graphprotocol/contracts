// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;

import "./IRewardsManager.sol";
import "../governance/Managed.sol";

contract RewardsManagerV1Storage is Managed {
    // -- State --

    uint256 public issuanceRate;
    uint256 public accRewardsPerSignal;
    uint256 public accRewardsPerSignalLastBlockUpdated;

    // Address of role allowed to deny rewards on subgraphs
    address public subgraphAvailabilityOracle;

    // Subgraph related rewards: subgraph deployment ID => subgraph rewards
    mapping(bytes32 => IRewardsManager.Subgraph) public subgraphs;

    // Subgraph denylist : subgraph deployment ID => block when added or zero (if not denied)
    mapping(bytes32 => uint256) public denylist;
}

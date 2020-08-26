pragma solidity ^0.6.12;

import "../governance/Managed.sol";

contract RewardsManagerV1Storage is Managed {
    // -- State --

    struct Subgraph {
        uint256 accRewardsForSubgraph;
        uint256 accRewardsForSubgraphSnapshot;
        uint256 accRewardsPerSignalSnapshot;
        uint256 accRewardsPerAllocatedToken;
    }

    uint256 public issuanceRate;
    uint256 public accRewardsPerSignal;
    uint256 public accRewardsPerSignalLastBlockUpdated;

    // Address of role allowed to deny rewards on subgraphs
    address public enforcer;

    // Subgraph related rewards: subgraph deployment ID => subgraph rewards
    mapping(bytes32 => Subgraph) public subgraphs;
    // Indexer distributed rewards: indexer address => unclaimed rewards
    mapping(address => uint256) public indexerRewards;
    // Subgraph denylist : subgraph deployment ID => block when added or zero (if not denied)
    mapping(bytes32 => uint256) public denylist;
}

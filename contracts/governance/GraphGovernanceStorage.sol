pragma solidity ^0.6.12;

import "./Governed.sol";
import "./IGraphGovernance.sol";

contract GraphGovernanceStorage is Governed {
    // -- State --

    // Proposals are identified by a bytes32 IPFS Hash
    // The hash resource has the content for that proposal
    mapping(bytes32 => IGraphGovernance.ProposalStatus) internal _proposals;
    mapping(address => bool) internal _proposers;
}

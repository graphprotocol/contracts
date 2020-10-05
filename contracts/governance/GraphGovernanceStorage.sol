pragma solidity ^0.6.12;

import "./Governed.sol";
import "./IGraphGovernance.sol";

contract GraphGovernanceStorage is Governed {
    // -- State --

    mapping(bytes32 => IGraphGovernance.ProposalStatus) internal _proposals;
    mapping(address => bool) internal _proposers;
}

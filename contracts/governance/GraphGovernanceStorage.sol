// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "./Governed.sol";
import "./IGraphGovernance.sol";

contract GraphGovernanceV1Storage is Governed {
    struct Proposal {
        bytes32 votesProof; // IPFS hash of signed votes
        IGraphGovernance.ProposalResolution resolution;
    }

    // -- State --

    // Proposals are identified by a IPFS Hash used as proposalId
    // The `proposalId` must link to the content of the proposal
    mapping(bytes32 => Proposal) public proposals;
}

// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "./Governed.sol";
import "./IGraphGovernance.sol";

contract GraphGovernanceV1Storage is Governed {
    // Graph Governance Proposal storage struct (GGP)
    struct Proposal {
        bytes32 votes; // IPFS hash of signed votes
        bytes32 metadata; // Additional info that can be linked
        IGraphGovernance.ProposalResolution resolution;
    }

    // -- State --

    // Proposals are identified by a base58 decoded IPFS Hash used as proposalId
    // The `proposalId` must link to the content of the proposal
    mapping(bytes32 => Proposal) public proposals;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

interface IGraphGovernance {
    enum ProposalResolution { Null, Accepted, Rejected }

    // -- Proposals --

    function isProposalCreated(bytes32 _proposalId) external view returns (bool);

    function createProposal(
        bytes32 _proposalId,
        bytes32 _votes,
        bytes32 _metadata,
        ProposalResolution _resolution
    ) external;

    function updateProposal(
        bytes32 _proposalId,
        bytes32 _votes,
        bytes32 _metadata,
        ProposalResolution _resolution
    ) external;
}

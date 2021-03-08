// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

interface IGraphGovernance {
    enum ProposalResolution { Null, Accepted, Rejected }

    // -- Proposals --

    function isProposalCreated(bytes32 _metadata) external view returns (bool);

    function createProposal(
        bytes32 _pid,
        bytes32 _votesProof,
        ProposalResolution _resolution
    ) external;

    function updateProposal(
        bytes32 _pid,
        bytes32 _votesProof,
        ProposalResolution _resolution
    ) external;
}

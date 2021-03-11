// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "../upgrades/GraphUpgradeable.sol";

import "./GraphGovernanceStorage.sol";

/**
 * @title Graph Governance Contract
 * @notice Governance contract used to inscribe Graph Council and community votes.
 */
contract GraphGovernance is GraphGovernanceV1Storage, GraphUpgradeable, IGraphGovernance {
    // -- Events --

    event ProposalCreated(
        address submitter,
        bytes32 proposalId,
        bytes32 votes,
        bytes32 metadata,
        ProposalResolution resolution
    );
    event ProposalUpdated(
        address submitter,
        bytes32 proposalId,
        bytes32 votes,
        bytes32 metadata,
        ProposalResolution resolution
    );

    /**
     * @notice Initialize this contract.
     */
    function initialize(address _governor) public onlyImpl {
        Governed._initialize(_governor);
    }

    // -- Proposals --

    /**
     * @notice Return whether the proposal is created.
     * @param _proposalId Proposal identifier
     * @return True if the proposal is already created
     */
    function isProposalCreated(bytes32 _proposalId) public view override returns (bool) {
        return proposals[_proposalId].votes != 0;
    }

    /**
     * @notice Submit a new proposal.
     * @param _proposalId Proposal identifier. This is an IPFS hash to the content of the proposal
     * @param _votes An IPFS hash of the collection of signatures for each vote
     * @param _metadata A bytes32 field to attach metadata to the proposal if needed
     * @param _resolution Resolution choice, either Accepted or Rejected
     */
    function createProposal(
        bytes32 _proposalId,
        bytes32 _votes,
        bytes32 _metadata,
        ProposalResolution _resolution
    ) external override onlyGovernor {
        require(_proposalId != 0x0, "!proposalId");
        require(_votes != 0x0, "!votes");
        require(_resolution != ProposalResolution.Null, "!resolved");
        require(!isProposalCreated(_proposalId), "proposed");

        proposals[_proposalId] = Proposal({ votes: _votes, metadata: _metadata, resolution: _resolution });
        emit ProposalCreated(msg.sender, _proposalId, _votes, _metadata, _resolution);
    }

    /**
     * @notice Updates an existing proposal.
     * @param _proposalId Proposal identifier. This is an IPFS hash to the content of the proposal
     * @param _votes An IPFS hash of the collection of signatures for each vote
     * @param _metadata A bytes32 field to attach metadata to the proposal if needed
     * @param _resolution Resolution choice, either Accepted or Rejected
     */
    function updateProposal(
        bytes32 _proposalId,
        bytes32 _votes,
        bytes32 _metadata,
        ProposalResolution _resolution
    ) external override onlyGovernor {
        require(_proposalId != 0x0, "!proposalId");
        require(_votes != 0x0, "!votes");
        require(_resolution != ProposalResolution.Null, "!resolved");
        require(isProposalCreated(_proposalId), "!proposed");

        proposals[_proposalId] = Proposal({ votes: _votes, metadata: _metadata, resolution: _resolution });
        emit ProposalUpdated(msg.sender, _proposalId, _votes, _metadata, _resolution);
    }
}

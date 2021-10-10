// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../upgrades/GraphUpgradeable.sol";

import "./GraphGovernanceStorage.sol";

/**
 * @title Graph Governance Contract
 * @notice Governance contract used to inscribe Graph Council and community votes.
 */
contract GraphGovernance is GraphGovernanceV1Storage, GraphUpgradeable, IGraphGovernance {
    // -- Events --

    /**
     * @dev Emitted when `governor` calls createProposal()
     */
    event ProposalCreated(
        bytes32 indexed proposalId,
        bytes32 votes,
        bytes32 metadata,
        ProposalResolution resolution
    );
    /**
     * @dev Emitted when `governor` calls updateProposal()
     */
    event ProposalUpdated(
        bytes32 indexed proposalId,
        bytes32 votes,
        bytes32 metadata,
        ProposalResolution resolution
    );

    /**
     * @notice Initialize this contract.
     */
    function initialize(address _governor) public onlyImpl {
        require(_governor != address(0), "governor != 0");
        Governed._initialize(_governor);
        emit NewOwnership(address(0), _governor);
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
     * @notice Updates an existing on chain proposal that links to a Graph Governance Proposal (GGP)
     * IPFS hashes are base58 decoded, and have the first two bytes 'Qm' cut off to fit in bytes32
     * @param _proposalId Proposal identifier. This is an IPFS hash to the content of the GGP
     * @param _votes An IPFS hash of the collection of signatures for each vote of the GGP.
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

        proposals[_proposalId] = Proposal({
            votes: _votes,
            metadata: _metadata,
            resolution: _resolution
        });
        emit ProposalCreated(_proposalId, _votes, _metadata, _resolution);
    }

    /**
     * @notice Updates an existing on chain proposal that links to a Graph Governance Proposal (GGP)
     * IPFS hashes are base58 decoded, and have the first two bytes 'Qm' cut off to fit in bytes32
     * The council has full power to create and vote on proposals - thus updated proposals can
     * change past votes, metadata, and even resolutions if necessary.
     * @param _proposalId Proposal identifier. This is an IPFS hash to the content of the GGP
     * @param _votes An IPFS hash of the collection of signatures for each vote of the GGP.
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

        proposals[_proposalId] = Proposal({
            votes: _votes,
            metadata: _metadata,
            resolution: _resolution
        });
        emit ProposalUpdated(_proposalId, _votes, _metadata, _resolution);
    }
}

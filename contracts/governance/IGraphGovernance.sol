// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

interface IGraphGovernance {
    /**
     * @dev The three states of a Proposal. Null can never be set.
     */
    enum ProposalResolution {
        Null,
        Accepted,
        Rejected
    }

    // -- Proposals --

    /**
     * @notice Return whether the proposal is created.
     * @param _proposalId Proposal identifier
     * @return True if the proposal is already created
     */
    function isProposalCreated(bytes32 _proposalId) external view returns (bool);

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
    ) external;

    /**
     * @notice Updates an existing on chain proposal that links to a Graph Governance Proposal (GGP)
     * IPFS hashes are base58 decoded, and have the first two bytes 'Qm' cut off to fit in bytes32
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
    ) external;
}

pragma solidity ^0.6.12;

interface IGraphGovernance {
    enum ProposalStatus { Null, Unresolved, Approved, Rejected }

    // -- Proposers --

    function isProposer(address _account) external view returns (bool);

    function setProposer(address _account, bool _allowed) external;

    function setProposerMany(address[] calldata _accounts, bool[] calldata _alloweds) external;

    // -- Proposals --

    function isProposalCreated(bytes32 _metadata) external view returns (bool);

    function isProposalResolved(bytes32 _metadata) external view returns (bool);

    function getProposalStatus(bytes32 _metadata) external view returns (ProposalStatus);

    function createProposal(bytes32 _metadata) external;

    function approveProposal(bytes32 _metadata) external;

    function rejectProposal(bytes32 _metadata) external;
}

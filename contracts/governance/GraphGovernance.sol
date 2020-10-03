pragma solidity ^0.6.12;

import "./Governed.sol";

contract GraphGovernance is Governed {
    enum ProposalStatus { Null, Unresolved, Approved, Rejected }

    // -- State --

    mapping(bytes32 => ProposalStatus) private _proposals;
    mapping(address => bool) private _proposers;

    // -- Events --

    event ProposalCreated(address submitter, bytes32 metadata);
    event ProposalApproved(address approver, bytes32 metadata);
    event ProposalRejected(address approver, bytes32 metadata);

    event ProposerUpdated(address proposer, bool allowed);

    modifier onlyProposer() {
        require(_proposers[msg.sender] == true, "!proposer");
        _;
    }

    constructor() public {
        Governed._initialize(msg.sender);
    }

    // -- Proposers --

    function isProposer(address _account) public view returns (bool) {
        return _proposers[_account];
    }

    function setProposer(address _account, bool _allowed) public onlyGovernor {
        _setProposer(_account, _allowed);
    }

    function setProposers(address[] calldata _accounts, bool[] calldata _alloweds)
        public
        onlyGovernor
    {
        for (uint32 i = 0; i < _accounts.length; i++) {
            _setProposer(_accounts[i], _alloweds[i]);
        }
    }

    function _setProposer(address _account, bool _allowed) internal {
        _proposers[_account] = _allowed;
        emit ProposerUpdated(_account, _allowed);
    }

    // -- Proposals --

    function isProposalCreated(bytes32 _metadata) public view returns (bool) {
        return _proposals[_metadata] != ProposalStatus.Null;
    }

    function isProposalResolved(bytes32 _metadata) public view returns (bool) {
        return isProposalCreated(_metadata) && _proposals[_metadata] != ProposalStatus.Unresolved;
    }

    function getProposalStatus(bytes32 _metadata) public view returns (ProposalStatus) {
        return _proposals[_metadata];
    }

    function createProposal(bytes32 _metadata) public onlyProposer {
        require(_metadata != 0x0, "!metadata");
        require(!isProposalCreated(_metadata), "exists");

        _proposals[_metadata] = ProposalStatus.Unresolved;
        emit ProposalCreated(msg.sender, _metadata);
    }

    function approveProposal(bytes32 _metadata) public onlyGovernor {
        require(!isProposalResolved(_metadata), "resolved");

        _proposals[_metadata] = ProposalStatus.Approved;
        emit ProposalApproved(msg.sender, _metadata);
    }

    function rejectProposal(bytes32 _metadata) public onlyGovernor {
        require(!isProposalResolved(_metadata), "resolved");

        _proposals[_metadata] = ProposalStatus.Rejected;
        emit ProposalRejected(msg.sender, _metadata);
    }
}

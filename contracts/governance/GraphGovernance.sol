pragma solidity ^0.6.12;

import "../upgrades/GraphUpgradeable.sol";

import "./GraphGovernanceStorage.sol";

contract GraphGovernance is GraphGovernanceStorage, GraphUpgradeable, IGraphGovernance {
    // -- Events --

    event ProposalCreated(address submitter, bytes32 metadata);
    event ProposalApproved(address approver, bytes32 metadata);
    event ProposalRejected(address approver, bytes32 metadata);

    event ProposerUpdated(address proposer, bool allowed);

    modifier onlyProposer() {
        require(_proposers[msg.sender] == true, "!proposer");
        _;
    }

    /**
     * @dev Initialize this contract.
     */
    function initialize(address _governor) public onlyImpl {
        Governed._initialize(_governor);
    }

    /**
     * @dev Accept to be an implementation of proxy and run initializer.
     * @param _proxy Graph proxy delegate caller
     */
    function acceptProxy(IGraphProxy _proxy, address _governor) external {
        // Accept to be the implementation for this proxy
        _acceptUpgrade(_proxy);

        // Initialization
        GraphGovernance(address(_proxy)).initialize(_governor);
    }

    // -- Proposers --

    /**
     * @dev Return whether an account is proposer or not.
     * @param _account Account to check if it is proposer
     * @return Return true if the account is proposer
     */
    function isProposer(address _account) external override view returns (bool) {
        return _proposers[_account];
    }

    /**
     * @dev Set an account as proposer.
     * @param _account Account to set as proposerr
     * @param _allowed True if set as allowed
     */
    function setProposer(address _account, bool _allowed) external override onlyGovernor {
        _setProposer(_account, _allowed);
    }

    /**
     * @dev Set many accounts as proposers.
     * @param _accounts List of accounts to change proposer status
     * @param _alloweds List of booleans for new status of each account
     */
    function setProposerMany(address[] calldata _accounts, bool[] calldata _alloweds)
        external
        override
        onlyGovernor
    {
        for (uint32 i = 0; i < _accounts.length; i++) {
            _setProposer(_accounts[i], _alloweds[i]);
        }
    }

    /**
     * @dev Internal: Set an account as proposer.
     * @param _account Account to set as proposerr
     * @param _allowed True if set as allowed
     */
    function _setProposer(address _account, bool _allowed) internal {
        _proposers[_account] = _allowed;
        emit ProposerUpdated(_account, _allowed);
    }

    // -- Proposals --

    /**
     * @dev Get if proposal is created.
     * @param _metadata Proposal identifier
     * @return True if the proposal is already created
     */
    function isProposalCreated(bytes32 _metadata) public override view returns (bool) {
        return _proposals[_metadata] != ProposalStatus.Null;
    }

    /**
     * @dev Get if proposal is resolved.
     * @param _metadata Proposal identifier
     * @return True if the proposal is resolved (accepted, rejected)
     */
    function isProposalResolved(bytes32 _metadata) public override view returns (bool) {
        return isProposalCreated(_metadata) && _proposals[_metadata] != ProposalStatus.Unresolved;
    }

    /**
     * @dev Get the proposal status.
     * @param _metadata Proposal identifier
     * @return Proposal current status
     */
    function getProposalStatus(bytes32 _metadata) external override view returns (ProposalStatus) {
        return _proposals[_metadata];
    }

    /**
     * @dev Submit a new proposals. Can only be submitted by allowed proposers.
     * @param _metadata Proposal identifier. This is an IPFS hash to the content of the proposal
     */
    function createProposal(bytes32 _metadata) external override onlyProposer {
        require(_metadata != 0x0, "!metadata");
        require(!isProposalCreated(_metadata), "exists");

        _proposals[_metadata] = ProposalStatus.Unresolved;
        emit ProposalCreated(msg.sender, _metadata);
    }

    /**
     * @dev Approve a proposal. Can only by called by the governing multisig.
     * @param _metadata Proposal identifier. This is an IPFS hash to the content of the proposal
     */
    function approveProposal(bytes32 _metadata) external override onlyGovernor {
        require(!isProposalResolved(_metadata), "resolved");

        _proposals[_metadata] = ProposalStatus.Approved;
        emit ProposalApproved(msg.sender, _metadata);
    }

    /**
     * @dev Reject a proposal. Can only by called by the governing multisig.
     * @param _metadata Proposal identifier. This is an IPFS hash to the content of the proposal
     */
    function rejectProposal(bytes32 _metadata) external override onlyGovernor {
        require(!isProposalResolved(_metadata), "resolved");

        _proposals[_metadata] = ProposalStatus.Rejected;
        emit ProposalRejected(msg.sender, _metadata);
    }
}

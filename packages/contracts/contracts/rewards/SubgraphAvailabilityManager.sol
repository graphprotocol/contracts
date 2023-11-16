// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../governance/Governed.sol";

import { IRewardsManager } from "../rewards/IRewardsManager.sol";

/**
 * @title Subgraph Availability Manager
 * @dev Manages the availability of subgraphs by allowing oracles to vote on whether
 * a subgraph should be denied or not. When enough oracles have voted to deny or
 * allow a subgraph, it calls the RewardsManager Contract to set the correct state.
 * The number of oracles and the execution threshold are set at deployment time.
 * Only governance can set the oracles.
 */
contract SubgraphAvailabilityManager is Governed {
    // -- Immutable --

    uint256 public immutable maxOracles;
    uint256 public immutable executionThreshold;
    IRewardsManager private immutable rewardsManager;

    // -- State --

    uint256 public voteTimeLimit;
    address[] public oracles;
    mapping(bytes32 => mapping(uint256 => uint256)) public lastDenyVote;
    mapping(bytes32 => mapping(uint256 => uint256)) public lastAllowVote;

    // -- Events --

    /**
     * @dev Emitted when an oracle is set
     */
    event OracleSet(uint256 indexed index, address indexed oracle);

    /**
     * @dev Emitted when the vote time limit is set
     */
    event VoteTimeLimitSet(uint256 voteTimeLimit);

    /**
     * @dev Emitted when an oracle votes to deny or allow a subgraph
     */
    event OracleVote(
        bytes32 indexed subgraphDeploymentID,
        bool deny,
        uint256 oracleIndex,
        uint256 timestamp
    );

    // -- Modifiers --

    modifier onlyOracle(uint256 _oracleIndex) {
        require(_oracleIndex < maxOracles, "SAM: index out of bounds");
        require(msg.sender == oracles[_oracleIndex], "SAM: caller must be oracle");
        _;
    }

    // -- Constructor --

    /**
     * @dev Contract constructor
     * @param _governor Account that can set or remove oracles and set the vote time limit
     * @param _rewardsManager Address of the RewardsManager contract
     * @param _maxOracles Maximum number of oracles
     * @param _executionThreshold Number of votes required to execute a deny or allow call to the RewardsManager
     * @param _voteTimeLimit Vote time limit in seconds
     */
    constructor(
        address _governor,
        address _rewardsManager,
        uint256 _maxOracles,
        uint256 _executionThreshold,
        uint256 _voteTimeLimit
    ) {
        require(_governor != address(0), "SAM: governor must be set");
        require(_rewardsManager != address(0), "SAM: rewardsManager must be set");
        require(_maxOracles > 1, "SAM: maxOracles must be greater than 1");
        require(_executionThreshold > 1, "SAM: executionThreshold must be greater than 1");

        Governed._initialize(_governor);
        rewardsManager = IRewardsManager(_rewardsManager);

        maxOracles = _maxOracles;
        executionThreshold = _executionThreshold;
        voteTimeLimit = _voteTimeLimit;
        oracles = new address[](_maxOracles);

        // Initialize oracles array with empty addresses
        for (uint256 i = 0; i < _maxOracles; i++) {
            oracles[i] = address(0);
        }
    }

    // -- Functions --

    /**
     * @dev Set the vote time limit
     * @param _voteTimeLimit Vote time limit in seconds
     */
    function setVoteTimeLimit(uint256 _voteTimeLimit) external onlyGovernor {
        voteTimeLimit = _voteTimeLimit;
        emit VoteTimeLimitSet(_voteTimeLimit);
    }

    /**
     * @dev Set oracle address with index
     * @param _index Index of the oracle
     * @param _oracle Address of the oracle
     */
    function setOracle(uint256 _index, address _oracle) external onlyGovernor {
        require(_index < maxOracles, "SAM: index out of bounds");
        oracles[_index] = _oracle;
        emit OracleSet(_index, _oracle);
    }

    /**
     * @dev Vote deny or allow for a subgraph.
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny True to deny, false to allow
     * @param _oracleIndex Index of the oracle voting
     */
    function voteDenied(
        bytes32 _subgraphDeploymentID,
        bool _deny,
        uint256 _oracleIndex
    ) external onlyOracle(_oracleIndex) {
        _voteDenied(_subgraphDeploymentID, _deny, _oracleIndex);
    }

    /**
     * @dev Vote deny or allow for a subgraph.
     * When oracles cast their votes we store the timestamp of the vote.
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny True to deny, false to allow
     * @param _oracleIndex Index of the oracle voting
     */
    function _voteDenied(
        bytes32 _subgraphDeploymentID,
        bool _deny,
        uint256 _oracleIndex
    ) private {
        uint256 timestamp = block.timestamp;

        if (_deny) {
            _checkVotes(_subgraphDeploymentID, _deny, _oracleIndex);
            lastDenyVote[_subgraphDeploymentID][_oracleIndex] = timestamp;
        } else {
            _checkVotes(_subgraphDeploymentID, _deny, _oracleIndex);
            lastAllowVote[_subgraphDeploymentID][_oracleIndex] = timestamp;
        }

        emit OracleVote(_subgraphDeploymentID, _deny, _oracleIndex, timestamp);
    }

    /**
     * @dev Check if the execution threshold has been reached for a subgraph.
     * If execution threshold is reached we call the RewardsManager to set the correct state.
     * For a vote to be valid it needs to be within the vote time limit.
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny True to deny, false to allow
     * @param _oracleIndex Index of the oracle voting
     */
    function _checkVotes(
        bytes32 _subgraphDeploymentID,
        bool _deny,
        uint256 _oracleIndex
    ) private {
        // init with 1 for current oracle's vote
        uint256 votes = 1;

        // timeframe for a vote to be valid
        uint256 voteTimeValiditiy = block.timestamp - voteTimeLimit;

        // corresponding votes based on _deny for a subgraph deployment
        mapping(uint256 => uint256) storage lastVoteForSubgraph = _deny
            ? lastDenyVote[_subgraphDeploymentID]
            : lastAllowVote[_subgraphDeploymentID];

        for (uint256 i = 0; i < maxOracles; i++) {
            // check if oracle has voted, skip check for current oracle
            if (i != _oracleIndex && lastVoteForSubgraph[i] > voteTimeValiditiy) {
                votes++;
            }

            // check if execution threshold is reached
            if (votes == executionThreshold) {
                rewardsManager.setDenied(_subgraphDeploymentID, _deny);
                break;
            }
        }
    }
}

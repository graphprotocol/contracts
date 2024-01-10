// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import { Governed } from "../governance/Governed.sol";
import { IRewardsManager } from "../rewards/IRewardsManager.sol";

/**
 * @title Subgraph Availability Manager
 * @dev Manages the availability of subgraphs by allowing oracles to vote on whether
 * a subgraph should be denied rewards or not. When enough oracles have voted to deny or
 * allow rewards for a subgraph, it calls the RewardsManager Contract to set the correct
 * state. The oracles and the execution threshold are set at deployment time.
 * Only governance can update the oracles and voteTimeLimit.
 * Governor can transfer ownership to a new governor.
 */
contract SubgraphAvailabilityManager is Governed {
    using SafeMathUpgradeable for uint256;

    // -- Immutable --

    /// @notice Number of oracles
    uint256 public constant NUM_ORACLES = 5;

    /// @notice Number of votes required to execute a deny or allow call to the RewardsManager
    uint256 public immutable executionThreshold;

    /// @dev Address of the RewardsManager contract
    IRewardsManager private immutable rewardsManager;

    // -- State --

    /// @dev Nonce for generating votes on subgraph deployment IDs.
    /// Increased whenever oracles or voteTimeLimit change, to invalidate old votes.
    uint256 public currentNonce;

    /// @notice Time limit for a vote to be valid
    uint256 public voteTimeLimit;

    /// @notice Array of oracle addresses
    address[NUM_ORACLES] public oracles;

    /// @notice Mapping of current nonce to subgraph deployment ID to an array of timestamps of last deny vote
    /// currentNonce => subgraphDeploymentId => timestamp[oracleIndex]
    mapping(uint256 => mapping(bytes32 => uint256[NUM_ORACLES])) public lastDenyVote;

    /// @notice Mapping of  current nonce to subgraph deployment ID to an array of timestamp of last allow vote
    /// currentNonce => subgraphDeploymentId => timestamp[oracleIndex]
    mapping(uint256 => mapping(bytes32 => uint256[NUM_ORACLES])) public lastAllowVote;

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
        uint256 indexed oracleIndex,
        uint256 timestamp
    );

    // -- Modifiers --

    modifier onlyOracle(uint256 _oracleIndex) {
        require(_oracleIndex < NUM_ORACLES, "SAM: index out of bounds");
        require(msg.sender == oracles[_oracleIndex], "SAM: caller must be oracle");
        _;
    }

    // -- Constructor --

    /**
     * @dev Contract constructor
     * @param _governor Account that can set or remove oracles and set the vote time limit
     * @param _rewardsManager Address of the RewardsManager contract
     * @param _executionThreshold Number of votes required to execute a deny or allow call to the RewardsManager
     * @param _voteTimeLimit Vote time limit in seconds
     * @param _oracles Array of oracle addresses, must be NUM_ORACLES in length.
     */
    constructor(
        address _governor,
        address _rewardsManager,
        uint256 _executionThreshold,
        uint256 _voteTimeLimit,
        address[NUM_ORACLES] memory _oracles
    ) {
        require(_governor != address(0), "SAM: governor must be set");
        require(_rewardsManager != address(0), "SAM: rewardsManager must be set");
        require(
            _executionThreshold >= NUM_ORACLES.div(2).add(1),
            "SAM: executionThreshold too low"
        );

        // Oracles should not be address zero
        for (uint256 i = 0; i < _oracles.length; i++) {
            address oracle = _oracles[i];
            require(oracle != address(0), "SAM: oracle cannot be address zero");
            oracles[i] = oracle;
            emit OracleSet(i, oracle);
        }

        Governed._initialize(_governor);
        rewardsManager = IRewardsManager(_rewardsManager);

        executionThreshold = _executionThreshold;
        voteTimeLimit = _voteTimeLimit;
    }

    // -- Functions --

    /**
     * @dev Set the vote time limit. Refreshes all existing votes by incrementing the current nonce.
     * @param _voteTimeLimit Vote time limit in seconds
     */
    function setVoteTimeLimit(uint256 _voteTimeLimit) external onlyGovernor {
        voteTimeLimit = _voteTimeLimit;
        currentNonce++;
        emit VoteTimeLimitSet(_voteTimeLimit);
    }

    /**
     * @dev Set oracle address with index. Refreshes all existing votes by incrementing the current nonce.
     * @param _index Index of the oracle
     * @param _oracle Address of the oracle
     */
    function setOracle(uint256 _index, address _oracle) external onlyGovernor {
        require(_index < NUM_ORACLES, "SAM: index out of bounds");
        require(_oracle != address(0), "SAM: oracle cannot be address zero");

        oracles[_index] = _oracle;
        // Increment the current nonce to refresh all existing votes for subgraph deployment IDs
        currentNonce++;

        emit OracleSet(_index, _oracle);
    }

    /**
     * @dev Vote deny or allow for a subgraph.
     * NOTE: Can only be called by an oracle.
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny True to deny, false to allow
     * @param _oracleIndex Index of the oracle voting
     */
    function vote(
        bytes32 _subgraphDeploymentID,
        bool _deny,
        uint256 _oracleIndex
    ) external onlyOracle(_oracleIndex) {
        _vote(_subgraphDeploymentID, _deny, _oracleIndex);
    }

    /**
     * @dev Vote deny or allow for many subgraphs.
     * NOTE: Can only be called by an oracle.
     * @param _subgraphDeploymentID Array of subgraph deployment IDs
     * @param _deny Array of booleans, true to deny, false to allow
     * @param _oracleIndex Index of the oracle voting
     */
    function voteMany(
        bytes32[] calldata _subgraphDeploymentID,
        bool[] calldata _deny,
        uint256 _oracleIndex
    ) external onlyOracle(_oracleIndex) {
        require(_subgraphDeploymentID.length == _deny.length, "!length");
        for (uint256 i = 0; i < _subgraphDeploymentID.length; i++) {
            _vote(_subgraphDeploymentID[i], _deny[i], _oracleIndex);
        }
    }

    /**
     * @dev Vote deny or allow for a subgraph.
     * When oracles cast their votes we store the timestamp of the vote.
     * Check if the execution threshold has been reached for a subgraph.
     * If execution threshold is reached we call the RewardsManager to set the correct state.
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny True to deny, false to allow
     * @param _oracleIndex Index of the oracle voting
     */
    function _vote(
        bytes32 _subgraphDeploymentID,
        bool _deny,
        uint256 _oracleIndex
    ) private {
        uint256 timestamp = block.timestamp;

        // corresponding votes based on _deny for a subgraph deployment
        uint256[NUM_ORACLES] storage lastVoteForSubgraph = _deny
            ? lastDenyVote[currentNonce][_subgraphDeploymentID]
            : lastAllowVote[currentNonce][_subgraphDeploymentID];
        lastVoteForSubgraph[_oracleIndex] = timestamp;

        // check if execution threshold is reached, if it is call the RewardsManager
        if (checkVotes(_subgraphDeploymentID, _deny)) {
            rewardsManager.setDenied(_subgraphDeploymentID, _deny);
        }

        emit OracleVote(_subgraphDeploymentID, _deny, _oracleIndex, timestamp);
    }

    /**
     * @dev Check if the execution threshold has been reached for a subgraph.
     * For a vote to be valid it needs to be within the vote time limit.
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny True to deny, false to allow
     * @return True if execution threshold is reached
     */
    function checkVotes(bytes32 _subgraphDeploymentID, bool _deny) public view returns (bool) {
        uint256 votes = 0;

        // timeframe for a vote to be valid
        uint256 voteTimeValidity = block.timestamp - voteTimeLimit;

        // corresponding votes based on _deny for a subgraph deployment
        uint256[NUM_ORACLES] storage lastVoteForSubgraph = _deny
            ? lastDenyVote[currentNonce][_subgraphDeploymentID]
            : lastAllowVote[currentNonce][_subgraphDeploymentID];

        for (uint256 i = 0; i < NUM_ORACLES; i++) {
            // check if vote is within the vote time limit
            if (lastVoteForSubgraph[i] > voteTimeValidity) {
                votes++;
            }

            // check if execution threshold is reached
            if (votes == executionThreshold) {
                return true;
            }
        }

        return false;
    }
}

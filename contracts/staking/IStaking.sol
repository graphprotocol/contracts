pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

interface IStaking {
    // -- Allocation Data --

    /**
     * @dev Possible states an allocation can be
     * States:
     * - Null = indexer == address(0)
     * - Active = not Null && tokens > 0
     * - Settled = Active && settledAtEpoch != 0
     * - Finalized = Settling && settledAtEpoch + channelDisputeEpochs > now()
     * - Claimed = not Null && tokens == 0
     */
    enum AllocationState { Null, Active, Settled, Finalized, Claimed }

    /**
     * @dev GRT stake allocation to a channel
     * An allocation is created in the allocate() function and consumed in claim()
     */
    struct Allocation {
        address indexer;
        bytes32 subgraphDeploymentID;
        uint256 tokens; // Tokens allocated to a SubgraphDeployment
        uint256 createdAtEpoch; // Epoch when it was created
        uint256 settledAtEpoch; // Epoch when it was settled
        uint256 collectedFees; // Collected fees from channels
        uint256 effectiveAllocation; // Effective allocation when settled
        address channelProxy; // Caller address of the collect() function
    }

    // -- Delegation Data --

    /**
     * @dev Delegation pool information. One per indexer.
     */
    struct DelegationPool {
        uint32 cooldownBlocks; // Blocks to wait before updating parameters
        uint32 indexingRewardCut; // in PPM
        uint32 queryFeeCut; // in PPM
        uint256 updatedAtBlock; // Block when the pool was last updated
        uint256 tokens; // Total tokens as pool reserves
        uint256 shares; // Total shares minted in the pool
        mapping(address => Delegation) delegators; // Mapping of delegator => Delegation
    }

    /**
     * @dev Individual delegation data of a delegator in a pool.
     */
    struct Delegation {
        uint256 shares; // Shares owned by a delegator in the pool
        uint256 tokensLocked; // Tokens locked for undelegation
        uint256 tokensLockedUntil; // Block when locked tokens can be withdrawn
    }

    // -- Configuration --

    function setCuration(address _curation) external;

    function setCurationPercentage(uint32 _percentage) external;

    function setProtocolPercentage(uint32 _percentage) external;

    function setChannelDisputeEpochs(uint256 _channelDisputeEpochs) external;

    function setMaxAllocationEpochs(uint256 _maxAllocationEpochs) external;

    function setDelegationParametersCooldown(uint32 _blocks) external;

    function setDelegationCapacity(uint32 _delegationCapacity) external;

    function setDelegationParameters(
        uint32 _indexingRewardCut,
        uint32 _queryFeeCut,
        uint32 _cooldownBlocks
    ) external;

    function setSlasher(address _slasher, bool _allowed) external;

    function setThawingPeriod(uint256 _thawingPeriod) external;

    // -- Operation --

    function setOperator(address _operator, bool _allowed) external;

    // -- Staking --

    function stake(uint256 _tokens) external;

    function unstake(uint256 _tokens) external;

    function slash(
        address _indexer,
        uint256 _tokens,
        uint256 _reward,
        address _beneficiary
    ) external;

    function withdraw() external;

    // -- Delegation --

    function delegate(address _indexer, uint256 _tokens) external;

    function undelegate(address _indexer, uint256 _shares) external;

    function redelegate(
        address _srcIndexer,
        address _dstIndexer,
        uint256 _shares
    ) external;

    // -- Channel management and allocations --

    function allocate(
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        bytes calldata _channelPubKey,
        address _channelProxy,
        uint256 _price
    ) external;

    function allocateFrom(
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        bytes calldata _channelPubKey,
        address _channelProxy,
        uint256 _price
    ) external;

    function settle(address _channelID) external;

    function collect(uint256 _tokens, address _channelID) external;

    function claim(address _channelID, bool _restake) external;

    // -- Getters and calculations --

    function isChannel(address _channelID) external view returns (bool);

    function hasStake(address _indexer) external view returns (bool);

    function getAllocation(address _channelID) external view returns (Allocation memory);

    function getAllocationState(address _channelID) external view returns (AllocationState);

    function getDelegationShares(address _indexer, address _delegator)
        external
        view
        returns (uint256);

    function getDelegationTokens(address _indexer, address _delegator)
        external
        view
        returns (uint256);

    function getIndexerStakedTokens(address _indexer) external view returns (uint256);

    function getIndexerCapacity(address _indexer) external view returns (uint256);
}

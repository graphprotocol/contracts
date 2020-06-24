pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

interface IStaking {
    // -- Allocation Data --

    struct Allocation {
        address indexer;
        bytes32 subgraphDeploymentID;
        uint256 tokens; // Tokens allocated to a SubgraphDeployment
        uint256 createdAtEpoch; // Epoch when it was created
        uint256 settledAtEpoch; // Epoch when it was settled
        uint256 collectedFees;
        uint256 effectiveAllocation;
    }

    // -- Delegation Data --

    struct DelegationPool {
        uint256 cooldownBlocks;
        uint256 indexingRewardCut; // in PPM
        uint256 queryFeeCut; // in PPM
        uint256 updatedAtBlock;
        uint256 tokens;
        uint256 shares;
        mapping(address => uint256) delegatorShares; // Mapping of delegator => shares
    }

    // -- Configuration --

    function setCuration(address _curation) external;

    function setCurationPercentage(uint256 _percentage) external;

    function setChannelDisputeEpochs(uint256 _channelDisputeEpochs) external;

    function setMaxAllocationEpochs(uint256 _maxAllocationEpochs) external;

    function setDelegationParametersCooldown(uint256 _blocks) external;

    function setDelegationCapacity(uint256 _delegationCapacity) external;

    function setDelegationParameters(
        uint256 _indexingRewardCut,
        uint256 _queryFeeCut,
        uint256 _cooldownBlocks
    ) external;

    function setSlasher(address _slasher, bool _allowed) external;

    function setThawingPeriod(uint256 _thawingPeriod) external;

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

    function settle(address _channelID) external;

    function collect(uint256 _tokens) external;

    function claim(address _channelID, bool _restake) external;

    // -- Getters and calculations --

    function isChannel(address _channelID) external view returns (bool);

    function hasStake(address _indexer) external view returns (bool);

    function getAllocation(address _channelID) external view returns (Allocation memory);

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

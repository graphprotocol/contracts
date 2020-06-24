pragma solidity ^0.6.4;

interface ICuration {
    // -- Configuration --

    function setDefaultReserveRatio(uint256 _defaultReserveRatio) external;

    function setStaking(address _staking) external;

    function setMinimumCurationStake(uint256 _minimumCurationStake) external;

    function setWithdrawalFeePercentage(uint256 _percentage) external;

    // -- Curation --

    function stake(bytes32 _subgraphDeploymentID, uint256 _tokens) external;

    function redeem(bytes32 _subgraphDeploymentID, uint256 _shares) external;

    function collect(bytes32 _subgraphDeploymentID, uint256 _tokens) external;

    // -- Getters --

    function isCurated(bytes32 _subgraphDeploymentID) external view returns (bool);
}

pragma solidity ^0.6.4;

interface ICuration {
    // -- Configuration --

    function setDefaultReserveRatio(uint32 _defaultReserveRatio) external;

    function setStaking(address _staking) external;

    function setMinimumCurationStake(uint256 _minimumCurationStake) external;

    function setWithdrawalFeePercentage(uint32 _percentage) external;

    // -- Curation --

    function mint(bytes32 _subgraphDeploymentID, uint256 _tokens) external;

    function burn(bytes32 _subgraphDeploymentID, uint256 _signal) external;

    function collect(bytes32 _subgraphDeploymentID, uint256 _tokens) external;

    // -- Getters --

    function isCurated(bytes32 _subgraphDeploymentID) external view returns (bool);
}

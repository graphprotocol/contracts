pragma solidity ^0.6.4;

interface IRewardsManager {
    // -- Params --

    function setIssuanceRate(uint256 _issuanceRate) external;

    // -- Denylist --

    function setDenied(bytes32 _subgraphDeploymentID, bool _deny) external;

    function isDenied(bytes32 _subgraphDeploymentID) external returns (bool);

    // -- Getters --

    function getNewRewardsPerSignal() external view returns (uint256);

    function getAccRewardsPerSignal() external view returns (uint256);

    function getAccRewardsForSubgraph(bytes32 _subgraphDeploymentID)
        external
        view
        returns (uint256);

    function getAccRewardsPerAllocatedToken(bytes32 _subgraphDeploymentID)
        external
        view
        returns (uint256, uint256);

    function getRewards(address _allocationID) external view returns (uint256);

    // -- Updates --

    function updateAccRewardsPerSignal() external returns (uint256);

    function assignRewards(address _allocationID) external returns (uint256);

    function claim(bool _restake) external returns (uint256);

    // -- Hooks --

    function onSubgraphSignalUpdate(bytes32 _subgraphDeploymentID) external returns (uint256);

    function onSubgraphAllocationUpdate(bytes32 _subgraphDeploymentID) external returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IL2CurationLike {
    event Signalled(
        address indexed curator,
        bytes32 indexed subgraphDeploymentID,
        uint256 tokens,
        uint256 signal,
        uint256 curationTax
    );
    event Burned(address indexed curator, bytes32 indexed subgraphDeploymentID, uint256 tokens, uint256 signal);
    event Collected(bytes32 indexed subgraphDeploymentID, uint256 tokens);

    function initialize(
        address controller,
        address curationTokenMaster,
        uint32 curationTaxPercentage,
        uint256 minimumCurationDeposit
    ) external;

    function pools(
        bytes32 subgraphDeploymentID
    ) external view returns (uint256 tokens, uint32 reserveRatio, address gcs);

    function defaultReserveRatio() external view returns (uint32);

    function setDefaultReserveRatio(uint32 defaultReserveRatio) external;

    function minimumCurationDeposit() external view returns (uint256);

    function setMinimumCurationDeposit(uint256 minimumCurationDeposit) external;

    function curationTaxPercentage() external view returns (uint32);

    function setCurationTaxPercentage(uint32 percentage) external;

    function curationTokenMaster() external view returns (address);

    function setCurationTokenMaster(address curationTokenMaster) external;

    function subgraphService() external view returns (address);

    function setSubgraphService(address subgraphService) external;

    function mint(
        bytes32 subgraphDeploymentID,
        uint256 tokensIn,
        uint256 signalOutMin
    ) external returns (uint256 signalOut, uint256 curationTax);

    function mintTaxFree(bytes32 subgraphDeploymentID, uint256 tokensIn) external returns (uint256);

    function burn(bytes32 subgraphDeploymentID, uint256 signalIn, uint256 tokensOutMin) external returns (uint256);

    function collect(bytes32 subgraphDeploymentID, uint256 tokens) external;

    function isCurated(bytes32 subgraphDeploymentID) external view returns (bool);

    function getCuratorSignal(address curator, bytes32 subgraphDeploymentID) external view returns (uint256);

    function getCurationPoolSignal(bytes32 subgraphDeploymentID) external view returns (uint256);

    function getCurationPoolTokens(bytes32 subgraphDeploymentID) external view returns (uint256);

    function tokensToSignal(bytes32 subgraphDeploymentID, uint256 tokensIn) external view returns (uint256, uint256);

    function tokensToSignalNoTax(bytes32 subgraphDeploymentID, uint256 tokensIn) external view returns (uint256);

    function tokensToSignalToTokensNoTax(
        bytes32 subgraphDeploymentID,
        uint256 tokensIn
    ) external view returns (uint256);

    function signalToTokens(bytes32 subgraphDeploymentID, uint256 signalIn) external view returns (uint256);
}

pragma solidity ^0.6.12;

import "./GraphSignalToken.sol";

interface ICuration {
    // -- Pool --

    struct CurationPool {
        uint256 tokens; // GRT Tokens stored as reserves for the subgraph deployment
        uint32 reserveRatio; // Ratio for the bonding curve
        GraphSignalToken gst; // Signal token contract for this curation pool
    }

    // -- Configuration --

    function getTotalTokens() external view returns (uint256);

    function setDefaultReserveRatio(uint32 _defaultReserveRatio) external;

    function setMinimumCurationDeposit(uint256 _minimumCurationDeposit) external;

    function setWithdrawalFeePercentage(uint32 _percentage) external;

    // -- Curation --

    function mint(bytes32 _subgraphDeploymentID, uint256 _tokens) external returns (uint256);

    function burn(bytes32 _subgraphDeploymentID, uint256 _signal)
        external
        returns (uint256, uint256);

    function collect(bytes32 _subgraphDeploymentID, uint256 _tokens) external;

    // -- Getters --

    function isCurated(bytes32 _subgraphDeploymentID) external view returns (bool);

    function getCuratorSignal(address _curator, bytes32 _subgraphDeploymentID)
        external
        view
        returns (uint256);

    function getCurationPoolSignal(bytes32 _subgraphDeploymentID) external view returns (uint256);

    function getCurationPoolTokens(bytes32 _subgraphDeploymentID) external view returns (uint256);

    function tokensToSignal(bytes32 _subgraphDeploymentID, uint256 _tokens)
        external
        view
        returns (uint256);

    function signalToTokens(bytes32 _subgraphDeploymentID, uint256 _signal)
        external
        view
        returns (uint256, uint256);
}

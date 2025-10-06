// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

/**
 * @title Curation Interface
 * @author Edge & Node
 * @notice Interface for the Curation contract (and L2Curation too)
 */
interface ICuration {
    // -- Configuration --

    /**
     * @notice Update the default reserve ratio to `defaultReserveRatio`
     * @param defaultReserveRatio Reserve ratio (in PPM)
     */
    function setDefaultReserveRatio(uint32 defaultReserveRatio) external;

    /**
     * @notice Update the minimum deposit amount needed to intialize a new subgraph
     * @param minimumCurationDeposit Minimum amount of tokens required deposit
     */
    function setMinimumCurationDeposit(uint256 minimumCurationDeposit) external;

    /**
     * @notice Set the curation tax percentage to charge when a curator deposits GRT tokens.
     * @param percentage Curation tax percentage charged when depositing GRT tokens
     */
    function setCurationTaxPercentage(uint32 percentage) external;

    /**
     * @notice Set the master copy to use as clones for the curation token.
     * @param curationTokenMaster Address of implementation contract to use for curation tokens
     */
    function setCurationTokenMaster(address curationTokenMaster) external;

    // -- Curation --

    /**
     * @notice Deposit Graph Tokens in exchange for signal of a SubgraphDeployment curation pool.
     * @param subgraphDeploymentID Subgraph deployment pool from where to mint signal
     * @param tokensIn Amount of Graph Tokens to deposit
     * @param signalOutMin Expected minimum amount of signal to receive
     * @return Amount of signal minted
     * @return Amount of curation tax burned
     */
    function mint(
        bytes32 subgraphDeploymentID,
        uint256 tokensIn,
        uint256 signalOutMin
    ) external returns (uint256, uint256);

    /**
     * @notice Burn signal from the SubgraphDeployment curation pool
     * @param subgraphDeploymentID SubgraphDeployment the curator is returning signal
     * @param signalIn Amount of signal to return
     * @param tokensOutMin Expected minimum amount of tokens to receive
     * @return Tokens returned
     */
    function burn(bytes32 subgraphDeploymentID, uint256 signalIn, uint256 tokensOutMin) external returns (uint256);

    /**
     * @notice Assign Graph Tokens collected as curation fees to the curation pool reserve.
     * @param subgraphDeploymentID SubgraphDeployment where funds should be allocated as reserves
     * @param tokens Amount of Graph Tokens to add to reserves
     */
    function collect(bytes32 subgraphDeploymentID, uint256 tokens) external;

    // -- Getters --

    /**
     * @notice Check if any GRT tokens are deposited for a SubgraphDeployment.
     * @param subgraphDeploymentID SubgraphDeployment to check if curated
     * @return True if curated, false otherwise
     */
    function isCurated(bytes32 subgraphDeploymentID) external view returns (bool);

    /**
     * @notice Get the amount of signal a curator has in a curation pool.
     * @param curator Curator owning the signal tokens
     * @param subgraphDeploymentID Subgraph deployment curation pool
     * @return Amount of signal owned by a curator for the subgraph deployment
     */
    function getCuratorSignal(address curator, bytes32 subgraphDeploymentID) external view returns (uint256);

    /**
     * @notice Get the amount of signal in a curation pool.
     * @param subgraphDeploymentID Subgraph deployment curation pool
     * @return Amount of signal minted for the subgraph deployment
     */
    function getCurationPoolSignal(bytes32 subgraphDeploymentID) external view returns (uint256);

    /**
     * @notice Get the amount of token reserves in a curation pool.
     * @param subgraphDeploymentID Subgraph deployment curation pool
     * @return Amount of token reserves in the curation pool
     */
    function getCurationPoolTokens(bytes32 subgraphDeploymentID) external view returns (uint256);

    /**
     * @notice Calculate amount of signal that can be bought with tokens in a curation pool.
     * This function considers and excludes the deposit tax.
     * @param subgraphDeploymentID Subgraph deployment to mint signal
     * @param tokensIn Amount of tokens used to mint signal
     * @return Amount of signal that can be bought
     * @return Amount of tokens that will be burned as curation tax
     */
    function tokensToSignal(bytes32 subgraphDeploymentID, uint256 tokensIn) external view returns (uint256, uint256);

    /**
     * @notice Calculate number of tokens to get when burning signal from a curation pool.
     * @param subgraphDeploymentID Subgraph deployment to burn signal
     * @param signalIn Amount of signal to burn
     * @return Amount of tokens to get for the specified amount of signal
     */
    function signalToTokens(bytes32 subgraphDeploymentID, uint256 signalIn) external view returns (uint256);

    /**
     * @notice Tax charged when curators deposit funds.
     * Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
     * @return Curation tax percentage expressed in PPM
     */
    function curationTaxPercentage() external view returns (uint32);
}

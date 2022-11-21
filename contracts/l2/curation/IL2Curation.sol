// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

/**
 * @title Interface of the L2 Curation contract.
 */
interface IL2Curation {
    /**
     * @notice Deposit Graph Tokens in exchange for signal of a SubgraphDeployment curation pool.
     * @dev This function charges no tax and can only be called by GNS in specific scenarios (for now
     * only during an L1-L2 migration).
     * @param _subgraphDeploymentID Subgraph deployment pool from where to mint signal
     * @param _tokensIn Amount of Graph Tokens to deposit
     * @param _signalOutMin Expected minimum amount of signal to receive
     * @return Signal minted
     */
    function mintTaxFree(
        bytes32 _subgraphDeploymentID,
        uint256 _tokensIn,
        uint256 _signalOutMin
    ) external returns (uint256);

    /**
     * @notice Calculate amount of signal that can be bought with tokens in a curation pool,
     * without accounting for curation tax.
     * @param _subgraphDeploymentID Subgraph deployment for which to mint signal
     * @param _tokensIn Amount of tokens used to mint signal
     * @return Amount of signal that can be bought
     */
    function tokensToSignalNoTax(bytes32 _subgraphDeploymentID, uint256 _tokensIn)
        external
        view
        returns (uint256);
}

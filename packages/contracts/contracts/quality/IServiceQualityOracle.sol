// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6 || 0.8.30;

interface IServiceQualityOracle {
    /**
     * @notice Check if an indexer meets service quality requirements
     * @param _indexer Address of the indexer
     * @return True if the indexer meets requirements, false otherwise
     */
    function meetsRequirements(address _indexer) external view returns (bool);
}

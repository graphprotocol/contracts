// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import { IRewardsEligibilityOracle } from "@graphprotocol/common/contracts/quality/IRewardsEligibilityOracle.sol";

/**
 * @title InterfaceIdExtractor
 * @author Edge & Node
 * @notice Utility contract for extracting ERC-165 interface IDs from Solidity interfaces
 * @dev This contract is used during the build process to generate interface ID constants
 * that match Solidity's own calculations, ensuring consistency between tests and actual
 * interface implementations.
 */
contract InterfaceIdExtractor {
    /**
     * @notice Returns the ERC-165 interface ID for IRewardsEligibilityOracle
     * @return The interface ID as calculated by Solidity
     */
    function getIRewardsEligibilityOracleId() external pure returns (bytes4) {
        return type(IRewardsEligibilityOracle).interfaceId;
    }
}

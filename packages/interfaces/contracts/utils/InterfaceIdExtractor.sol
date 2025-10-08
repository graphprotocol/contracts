// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import { IRewardsManager } from "../contracts/rewards/IRewardsManager.sol";
import { IIssuanceTarget } from "../issuance/allocate/IIssuanceTarget.sol";
import { IERC165 } from "@openzeppelin/contracts/introspection/IERC165.sol";

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
     * @notice Returns the ERC-165 interface ID for IRewardsManager
     * @return The interface ID as calculated by Solidity
     */
    function getIRewardsManagerId() external pure returns (bytes4) {
        return type(IRewardsManager).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IIssuanceTarget
     * @return The interface ID as calculated by Solidity
     */
    function getIIssuanceTargetId() external pure returns (bytes4) {
        return type(IIssuanceTarget).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IERC165
     * @return The interface ID as calculated by Solidity
     */
    function getIERC165Id() external pure returns (bytes4) {
        return type(IERC165).interfaceId;
    }
}

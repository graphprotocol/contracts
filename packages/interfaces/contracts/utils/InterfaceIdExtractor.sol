// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import { IRewardsManager } from "../contracts/rewards/IRewardsManager.sol";
import { IIssuanceTarget } from "../issuance/allocate/IIssuanceTarget.sol";
import { IIssuanceAllocationDistribution } from "../issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceAllocationAdministration } from "../issuance/allocate/IIssuanceAllocationAdministration.sol";
import { IIssuanceAllocationStatus } from "../issuance/allocate/IIssuanceAllocationStatus.sol";
import { IRewardsEligibilityOracle } from "../issuance/eligibility/IRewardsEligibilityOracle.sol";
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
     * @notice Returns the ERC-165 interface ID for IIssuanceAllocationDistribution
     * @return The interface ID as calculated by Solidity
     */
    function getIIssuanceAllocationDistributionId() external pure returns (bytes4) {
        return type(IIssuanceAllocationDistribution).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IIssuanceAllocationAdministration
     * @return The interface ID as calculated by Solidity
     */
    function getIIssuanceAllocationAdministrationId() external pure returns (bytes4) {
        return type(IIssuanceAllocationAdministration).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IIssuanceAllocationStatus
     * @return The interface ID as calculated by Solidity
     */
    function getIIssuanceAllocationStatusId() external pure returns (bytes4) {
        return type(IIssuanceAllocationStatus).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IRewardsEligibilityOracle
     * @return The interface ID as calculated by Solidity
     */
    function getIRewardsEligibilityOracleId() external pure returns (bytes4) {
        return type(IRewardsEligibilityOracle).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IERC165
     * @return The interface ID as calculated by Solidity
     */
    function getIERC165Id() external pure returns (bytes4) {
        return type(IERC165).interfaceId;
    }
}

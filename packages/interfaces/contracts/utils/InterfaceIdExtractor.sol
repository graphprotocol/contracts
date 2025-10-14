// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import { IRewardsManager } from "../contracts/rewards/IRewardsManager.sol";
import { IIssuanceTarget } from "../issuance/allocate/IIssuanceTarget.sol";
import { IIssuanceAllocationDistribution } from "../issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceAllocationAdministration } from "../issuance/allocate/IIssuanceAllocationAdministration.sol";
import { IIssuanceAllocationStatus } from "../issuance/allocate/IIssuanceAllocationStatus.sol";
import { IIssuanceAllocationData } from "../issuance/allocate/IIssuanceAllocationData.sol";
import { ISendTokens } from "../issuance/allocate/ISendTokens.sol";
import { IRewardsEligibility } from "../issuance/eligibility/IRewardsEligibility.sol";
import { IRewardsEligibilityAdministration } from "../issuance/eligibility/IRewardsEligibilityAdministration.sol";
import { IRewardsEligibilityReporting } from "../issuance/eligibility/IRewardsEligibilityReporting.sol";
import { IRewardsEligibilityStatus } from "../issuance/eligibility/IRewardsEligibilityStatus.sol";
import { IPausableControl } from "../issuance/common/IPausableControl.sol";
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
     * @notice Returns the ERC-165 interface ID for IERC165
     * @return The interface ID as calculated by Solidity
     */
    function getIERC165Id() external pure returns (bytes4) {
        return type(IERC165).interfaceId;
    }

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
     * @notice Returns the ERC-165 interface ID for IRewardsEligibility
     * @return The interface ID as calculated by Solidity
     */
    function getIRewardsEligibilityId() external pure returns (bytes4) {
        return type(IRewardsEligibility).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IRewardsEligibilityAdministration
     * @return The interface ID as calculated by Solidity
     */
    function getIRewardsEligibilityAdministrationId() external pure returns (bytes4) {
        return type(IRewardsEligibilityAdministration).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IRewardsEligibilityReporting
     * @return The interface ID as calculated by Solidity
     */
    function getIRewardsEligibilityReportingId() external pure returns (bytes4) {
        return type(IRewardsEligibilityReporting).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IRewardsEligibilityStatus
     * @return The interface ID as calculated by Solidity
     */
    function getIRewardsEligibilityStatusId() external pure returns (bytes4) {
        return type(IRewardsEligibilityStatus).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IIssuanceAllocationData
     * @return The interface ID as calculated by Solidity
     */
    function getIIssuanceAllocationDataId() external pure returns (bytes4) {
        return type(IIssuanceAllocationData).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for ISendTokens
     * @return The interface ID as calculated by Solidity
     */
    function getISendTokensId() external pure returns (bytes4) {
        return type(ISendTokens).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IPausableControl
     * @return The interface ID as calculated by Solidity
     */
    function getIPausableControlId() external pure returns (bytes4) {
        return type(IPausableControl).interfaceId;
    }

    /**
     * @notice Returns the ERC-165 interface ID for IAccessControl
     * @dev IAccessControl is from OpenZeppelin Contracts v5. This package uses v3 which doesn't
     * have a separate IAccessControl interface file, so we use the hardcoded value which is
     * standard across OpenZeppelin versions.
     * @return The interface ID for OpenZeppelin's IAccessControl (0x7965db0b)
     */
    function getIAccessControlId() external pure returns (bytes4) {
        return 0x7965db0b;
    }
}

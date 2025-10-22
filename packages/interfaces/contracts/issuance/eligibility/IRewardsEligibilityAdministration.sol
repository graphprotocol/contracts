// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

import { IRewardsEligibilityEvents } from "./IRewardsEligibilityEvents.sol";

/**
 * @title IRewardsEligibilityAdministration
 * @author Edge & Node
 * @notice Interface for administrative operations on rewards eligibility
 * @dev Functions in this interface are restricted to accounts with OPERATOR_ROLE
 */
interface IRewardsEligibilityAdministration is IRewardsEligibilityEvents {
    /**
     * @notice Set the eligibility period for indexers
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param eligibilityPeriod New eligibility period in seconds
     * @return True if the state is as requested (eligibility period is set to the specified value)
     */
    function setEligibilityPeriod(uint256 eligibilityPeriod) external returns (bool);

    /**
     * @notice Set the oracle update timeout
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param oracleUpdateTimeout New timeout period in seconds
     * @return True if the state is as requested (timeout is set to the specified value)
     */
    function setOracleUpdateTimeout(uint256 oracleUpdateTimeout) external returns (bool);

    /**
     * @notice Set eligibility validation state
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param enabled True to enable eligibility validation, false to disable
     * @return True if successfully set (always the case for current code)
     */
    function setEligibilityValidation(bool enabled) external returns (bool);
}

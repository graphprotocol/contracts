// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

import { IProviderEligibility } from "./IProviderEligibility.sol";

/**
 * @title Interface for provider eligibility oracle configuration
 * @author Edge & Node
 * @notice Configures the provider eligibility oracle that determines which providers
 * are eligible for rewards or payments.
 */
interface IProviderEligibilityManagement {
    // -- Events --

    /**
     * @notice Emitted when the provider eligibility oracle is changed
     * @param oldOracle The previous oracle (IProviderEligibility(address(0)) means none)
     * @param newOracle The new oracle (IProviderEligibility(address(0)) means disabled)
     */
    event ProviderEligibilityOracleSet(IProviderEligibility indexed oldOracle, IProviderEligibility indexed newOracle);

    // -- Functions --

    /**
     * @notice Set the provider eligibility oracle.
     * @dev When set, {isEligible} delegates to this oracle.
     * When set to IProviderEligibility(address(0)), all providers are considered eligible (passthrough).
     * @param oracle The eligibility oracle (or IProviderEligibility(address(0)) to disable)
     */
    function setProviderEligibilityOracle(IProviderEligibility oracle) external;

    /**
     * @notice Get the current provider eligibility oracle
     * @return oracle The eligibility oracle (IProviderEligibility(address(0)) means disabled)
     */
    function getProviderEligibilityOracle() external view returns (IProviderEligibility oracle);
}

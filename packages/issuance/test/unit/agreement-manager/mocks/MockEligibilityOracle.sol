// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRewardsEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibility.sol";

/// @notice Simple mock eligibility oracle for testing SAM passthrough
contract MockEligibilityOracle is IRewardsEligibility {
    mapping(address => bool) public eligible;
    bool public defaultEligible;

    function setEligible(address indexer, bool _eligible) external {
        eligible[indexer] = _eligible;
    }

    function setDefaultEligible(bool _default) external {
        defaultEligible = _default;
    }

    function isEligible(address indexer) external view override returns (bool) {
        if (eligible[indexer]) return true;
        return defaultEligible;
    }
}

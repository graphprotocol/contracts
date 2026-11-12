// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable use-natspec

import { Governed } from "../governance/Governed.sol";

/**
 * @title GovernedMock contract
 * @dev Mock contract for testing Governed functionality
 */
contract GovernedMock is Governed {
    /**
     * @dev Constructor that initializes the contract with the deployer as governor
     */
    constructor() {
        Governed._initialize(msg.sender);
    }
}

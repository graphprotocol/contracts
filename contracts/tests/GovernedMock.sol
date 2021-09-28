// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;

import "../governance/Governed.sol";

/**
 * @title GovernedMock contract
 */
contract GovernedMock is Governed {
    constructor() {
        Governed._initialize(msg.sender);
    }
}

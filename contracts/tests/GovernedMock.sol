// SPDX-License-Identifier: UNLICENSED

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

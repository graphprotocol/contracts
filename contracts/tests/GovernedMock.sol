pragma solidity ^0.6.4;

import "../governance/Governed.sol";

/**
 * @title GovernedMock contract
 */
contract GovernedMock is Governed {
    constructor() public {
        Governed._initialize(msg.sender);
    }
}

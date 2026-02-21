// SPDX-License-Identifier: MIT
pragma solidity 0.8.27 || 0.8.33;

import { PartialControllerMock } from "./PartialControllerMock.t.sol";

contract InvalidControllerMock is PartialControllerMock {
    constructor() PartialControllerMock(new PartialControllerMock.Entry[](0)) {}
}

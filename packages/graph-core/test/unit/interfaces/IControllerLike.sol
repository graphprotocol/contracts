// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IController } from "@graphprotocol/interfaces/contracts/contracts/governance/IController.sol";

/// IController plus the `pauseGuardian` getter that Pausable exposes but IController does not.
interface IControllerLike is IController {
    function pauseGuardian() external view returns (address);
}

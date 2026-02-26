// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { ProvisionManager } from "../../../../contracts/data-service/utilities/ProvisionManager.sol";
import { GraphDirectory } from "../../../../contracts/utilities/GraphDirectory.sol";

contract ProvisionManagerImpl is GraphDirectory, ProvisionManager {
    constructor(address controller) GraphDirectory(controller) {}

    function onlyValidProvision_(address serviceProvider) public view onlyValidProvision(serviceProvider) {}

    function onlyAuthorizedForProvision_(
        address serviceProvider
    ) public view onlyAuthorizedForProvision(serviceProvider) {}
}

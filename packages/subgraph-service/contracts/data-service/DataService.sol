// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { GraphDirectory } from "./GraphDirectory.sol";
import { DataServiceV1Storage } from "./DataServiceStorage.sol";
import { IDataService } from "./IDataService.sol";
import { ProvisionManager } from "./utilities/ProvisionManager.sol";

abstract contract DataService is GraphDirectory, ProvisionManager, DataServiceV1Storage, IDataService {
    constructor(address _controller) GraphDirectory(_controller) {}
}

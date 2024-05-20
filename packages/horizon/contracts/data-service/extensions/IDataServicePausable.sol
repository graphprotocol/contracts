// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataService } from "../../interfaces/IDataService.sol";

interface IDataServicePausable is IDataService {
    function pause() external;
    function unpause() external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataService } from "./IDataService.sol";

interface IDataServicePausable is IDataService {
    event PauseGuardianSet(address indexed account, bool allowed);

    error DataServicePausableNotPauseGuardian(address account);

    function pause() external;

    function unpause() external;
}

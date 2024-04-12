// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataService } from "../IDataService.sol";

interface IDataServiceRescuable is IDataService {
    function rescueGRT(address _to, uint256 _amount) external;
    function rescueETH(address payable _to, uint256 _amount) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataService } from "../../interfaces/IDataService.sol";

interface IDataServiceRescuable is IDataService {
    function rescueGRT(address to, uint256 tokens) external;
    function rescueETH(address payable to, uint256 tokens) external;
}

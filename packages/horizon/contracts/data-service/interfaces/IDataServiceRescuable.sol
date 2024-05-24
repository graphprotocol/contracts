// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataService } from "./IDataService.sol";

interface IDataServiceRescuable is IDataService {
    /**
     * @dev Tokens rescued by the user
     */
    event TokensRescued(address indexed from, address indexed to, uint256 tokens);
    event RescuerSet(address indexed account, bool allowed);

    error DataServiceRescuableCannotRescueZero();
    error DataServiceRescuableNotRescuer(address account);

    function rescueGRT(address to, uint256 tokens) external;

    function rescueETH(address payable to, uint256 tokens) external;
}

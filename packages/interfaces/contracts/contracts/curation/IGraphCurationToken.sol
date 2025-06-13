// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IGraphCurationToken is IERC20Upgradeable {
    function initialize(address owner) external;

    function burnFrom(address account, uint256 amount) external;

    function mint(address to, uint256 amount) external;
}

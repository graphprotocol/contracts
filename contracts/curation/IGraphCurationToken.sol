// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGraphCurationToken is IERC20 {
    function burnFrom(address _account, uint256 _amount) external;

    function mint(address _to, uint256 _amount) external;
}

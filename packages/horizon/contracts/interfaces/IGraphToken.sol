// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGraphToken is IERC20 {
    // -- Mint and Burn --

    function burn(uint256 amount) external;

    function burnFrom(address from, uint256 amount) external;

    function mint(address to, uint256 amount) external;

    // -- Mint Admin --

    function addMinter(address account) external;

    function removeMinter(address account) external;

    function renounceMinter() external;

    // -- Permit --

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    // -- Allowance --

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    function isMinter(address account) external view returns (bool);
}

// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IGraphToken
 * @author Edge & Node
 * @notice Minimal interface for the Graph Token contract used by issuance contracts
 * @dev Extends IERC20 with mint capability. This interface is compatible with OZ 5.x.
 */
interface IGraphToken is IERC20 {
    /**
     * @notice Mints new tokens to a specified account
     * @dev Only callable by accounts with minter role
     * @param to The account to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;
}

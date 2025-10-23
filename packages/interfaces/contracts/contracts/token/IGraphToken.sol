// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

// Solhint linting fails for 0.8.0.
// solhint-disable-next-line import-path-check
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IGraphToken
 * @author Edge & Node
 * @notice Interface for the Graph Token contract
 * @dev Extends IERC20 with additional functionality for minting, burning, and permit
 */
interface IGraphToken is IERC20 {
    // -- Mint and Burn --

    /**
     * @notice Burns tokens from the caller's account
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) external;

    /**
     * @notice Burns tokens from a specified account (requires allowance)
     * @param from The account to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) external;

    /**
     * @notice Mints new tokens to a specified account
     * @dev Only callable by accounts with minter role
     * @param to The account to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    // -- Mint Admin --

    /**
     * @notice Adds a new minter account
     * @dev Only callable by accounts with appropriate permissions
     * @param account The account to grant minter role to
     */
    function addMinter(address account) external;

    /**
     * @notice Removes minter role from an account
     * @dev Only callable by accounts with appropriate permissions
     * @param account The account to revoke minter role from
     */
    function removeMinter(address account) external;

    /**
     * @notice Renounces minter role for the caller
     * @dev Allows a minter to voluntarily give up their minting privileges
     */
    function renounceMinter() external;

    /**
     * @notice Checks if an account has minter role
     * @param account The account to check
     * @return True if the account is a minter, false otherwise
     */
    function isMinter(address account) external view returns (bool);

    // -- Permit --

    /**
     * @notice Permit the spender to spend tokens on behalf of the owner.
     * @param owner Address of the token owner
     * @param spender Address of the token spender
     * @param value Amount of tokens to spend
     * @param deadline Expiration timestamp for the permit
     * @param v Recovery byte of the signature
     * @param r R value of the signature
     * @param s S value of the signature
     */
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

    /**
     * @notice Increases the allowance granted to a spender
     * @param spender The account whose allowance will be increased
     * @param addedValue The amount to increase the allowance by
     * @return True if the operation succeeded
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    /**
     * @notice Decreases the allowance granted to a spender
     * @param spender The account whose allowance will be decreased
     * @param subtractedValue The amount to decrease the allowance by
     * @return True if the operation succeeded
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
}

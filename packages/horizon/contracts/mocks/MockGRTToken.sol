// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";

/**
 * @title MockGRTToken
 * @author Edge & Node
 * @notice Mock implementation of the Graph Token for testing
 */
contract MockGRTToken is ERC20, IGraphToken {
    /**
     * @notice Constructor for the MockGRTToken
     */
    constructor() ERC20("Graph Token", "GRT") {}

    /**
     * @notice Burn tokens from the caller's account
     * @param tokens Amount of tokens to burn
     */
    function burn(uint256 tokens) external {
        _burn(msg.sender, tokens);
    }

    /**
     * @notice Burn tokens from a specific account
     * @param from Account to burn tokens from
     * @param tokens Amount of tokens to burn
     */
    function burnFrom(address from, uint256 tokens) external {
        _burn(from, tokens);
    }

    // -- Mint Admin --

    /**
     * @notice Add a minter (mock implementation - does nothing)
     * @param account Account to add as minter
     */
    function addMinter(address account) external {}

    /**
     * @notice Remove a minter (mock implementation - does nothing)
     * @param account Account to remove as minter
     */
    function removeMinter(address account) external {}

    /**
     * @notice Renounce minter role (mock implementation - does nothing)
     */
    function renounceMinter() external {}

    // -- Permit --

    /**
     * @notice Permit function for gasless approvals (mock implementation - does nothing)
     * @param owner Token owner
     * @param spender Spender address
     * @param value Amount to approve
     * @param deadline Deadline for the permit
     * @param v Recovery byte of the signature
     * @param r First 32 bytes of the signature
     * @param s Second 32 bytes of the signature
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {}

    // -- Allowance --

    /**
     * @notice Increase allowance (mock implementation - does nothing)
     * @param spender Spender address
     * @param addedValue Amount to add to allowance
     * @return Always returns false in mock
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {}

    /**
     * @notice Decrease allowance (mock implementation - does nothing)
     * @param spender Spender address
     * @param subtractedValue Amount to subtract from allowance
     * @return Always returns false in mock
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {}

    /**
     * @notice Check if an account is a minter (mock implementation - always returns false)
     * @param account Account to check
     * @return Always returns false in mock
     */
    function isMinter(address account) external view returns (bool) {}

    /**
     * @notice Mint tokens to an account
     * @param to Account to mint tokens to
     * @param tokens Amount of tokens to mint
     */
    function mint(address to, uint256 tokens) public {
        _mint(to, tokens);
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";

/**
 * @title MockGraphToken
 * @notice A mock implementation of the Graph Token for testing
 * @dev This contract implements the IGraphToken interface but doesn't directly inherit from it
 * to avoid conflicts with ERC20 functions. Instead, it implements the required functions.
 */
contract MockGraphToken is ERC20 {
    // Mapping of minters
    mapping(address => bool) private _minters;

    constructor() ERC20("Mock Graph Token", "MGRT") {
        // Add deployer as minter
        _minters[msg.sender] = true;
    }

    /**
     * @notice Mint new tokens
     * @param _to Address to mint tokens to
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    /**
     * @notice Burn tokens
     * @param _amount Amount of tokens to burn
     */
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }

    /**
     * @notice Burn tokens from a specific account
     * @param _from Address to burn tokens from
     * @param _amount Amount of tokens to burn
     */
    function burnFrom(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }

    /**
     * @notice Add a new minter
     * @param _account Address to add as minter
     */
    function addMinter(address _account) external {
        _minters[_account] = true;
    }

    /**
     * @notice Remove a minter
     * @param _account Address to remove as minter
     */
    function removeMinter(address _account) external {
        _minters[_account] = false;
    }

    /**
     * @notice Renounce minter role
     */
    function renounceMinter() external {
        _minters[msg.sender] = false;
    }

    /**
     * @notice Check if an account is a minter
     * @param _account Address to check
     * @return True if the account is a minter
     */
    function isMinter(address _account) external view returns (bool) {
        return _minters[_account];
    }

    /**
     * @notice Approve token allowance by validating a message signed by the holder
     * @param _owner Address of the token holder
     * @param _spender Address of the approved spender
     * @param _value Amount of tokens to approve the spender
     */
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256, // unused
        uint8, // unused
        bytes32, // unused
        bytes32 // unused
    ) external {
        // Mock implementation - just approve
        _approve(_owner, _spender, _value);
    }

    /**
     * @notice Increase allowance
     * @param spender Address of the spender
     * @param addedValue Amount to add to the allowance
     * @return True if the operation was successful
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

    // Custom error for decreased allowance below zero
    error AllowanceBelowZero();

    /**
     * @notice Decrease allowance
     * @param spender Address of the spender
     * @param subtractedValue Amount to subtract from the allowance
     * @return True if the operation was successful
     */

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        if (currentAllowance < subtractedValue) {
            revert AllowanceBelowZero();
        }
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    /**
     * @notice Bridge mint tokens to an address
     * @param _account Address to mint tokens to
     * @param _amount Amount of tokens to mint
     */
    function bridgeMint(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }

    /**
     * @notice Bridge burn tokens from an address
     * @param _account Address to burn tokens from
     * @param _amount Amount of tokens to burn
     */
    function bridgeBurn(address _account, uint256 _amount) external {
        _burn(_account, _amount);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DataServiceOwnable } from "./DataServiceOwnable.sol";
import { Denominations } from "../utils/Denominations.sol";

/**
 * @title Rescuable contract
 * @dev Allows a contract to have a function to rescue tokens sent by mistake.
 * The contract must implement the external rescueTokens function or similar,
 * that calls this contract's _rescueTokens.
 */
abstract contract DataServiceRescuable is DataServiceOwnable {
    /**
     * @dev Tokens rescued by the user
     */
    event TokensRescued(address indexed from, address indexed to, uint256 amount);

    error DataServiceRescuableCannotRescueZero();

    function rescueGRT(address _to, uint256 _amount) external onlyOwner {
        _rescueTokens(_to, address(graphToken), _amount);
    }

    function rescueETH(address payable _to, uint256 _amount) external onlyOwner {
        _rescueTokens(_to, Denominations.NATIVE_TOKEN, _amount);
    }

    /**
     * @dev Allows rescuing tokens sent to this contract
     * @param _to  Destination address to send the tokens
     * @param _token  Address of the token being rescued
     * @param _amount  Amount of tokens to pull
     */
    function _rescueTokens(address _to, address _token, uint256 _amount) internal {
        if (_amount == 0) revert DataServiceRescuableCannotRescueZero();

        if (Denominations.isNativeToken(_token)) payable(_to).transfer(_amount);
        else SafeERC20.safeTransfer(IERC20(_token), _to, _amount);

        emit TokensRescued(msg.sender, _to, _amount);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDataServiceRescuable } from "./IDataServiceRescuable.sol";

import { DataService } from "../DataService.sol";

import { Denominations } from "../libraries/Denominations.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Rescuable contract
 * @dev Allows a contract to have a function to rescue tokens sent by mistake.
 * The contract must implement the external rescueTokens function or similar,
 * that calls this contract's _rescueTokens.
 */
abstract contract DataServiceRescuable is DataService, IDataServiceRescuable {
    mapping(address rescuer => bool allowed) public rescuers;

    /**
     * @dev Tokens rescued by the user
     */
    event TokensRescued(address indexed from, address indexed to, uint256 amount);
    event RescuerSet(address indexed account, bool allowed);

    error DataServiceRescuableCannotRescueZero();
    error DataServiceRescuableNotRescuer(address account);

    modifier onlyRescuer() {
        if (!rescuers[msg.sender]) {
            revert DataServiceRescuableNotRescuer(msg.sender);
        }
        _;
    }

    function rescueGRT(address _to, uint256 _amount) external onlyRescuer {
        _rescueTokens(_to, address(GRAPH_TOKEN), _amount);
    }

    function rescueETH(address payable _to, uint256 _amount) external onlyRescuer {
        _rescueTokens(_to, Denominations.NATIVE_TOKEN, _amount);
    }

    function _setRescuer(address _rescuer, bool _allowed) internal {
        rescuers[_rescuer] = _allowed;
        emit RescuerSet(_rescuer, _allowed);
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

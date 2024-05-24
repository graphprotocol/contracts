// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDataServiceRescuable } from "../interfaces/IDataServiceRescuable.sol";

import { DataService } from "../DataService.sol";

import { Denominations } from "../../libraries/Denominations.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Rescuable contract
 * @dev Allows a contract to have a function to rescue tokens sent by mistake.
 * The contract must implement the external rescueTokens function or similar,
 * that calls this contract's _rescueTokens.
 */
abstract contract DataServiceRescuable is DataService, IDataServiceRescuable {
    mapping(address rescuer => bool allowed) public rescuers;

    modifier onlyRescuer() {
        require(rescuers[msg.sender], DataServiceRescuableNotRescuer(msg.sender));
        _;
    }

    function rescueGRT(address to, uint256 tokens) external onlyRescuer {
        _rescueTokens(to, address(_graphToken()), tokens);
    }

    function rescueETH(address payable to, uint256 tokens) external onlyRescuer {
        _rescueTokens(to, Denominations.NATIVE_TOKEN, tokens);
    }

    function _setRescuer(address _rescuer, bool _allowed) internal {
        rescuers[_rescuer] = _allowed;
        emit RescuerSet(_rescuer, _allowed);
    }

    /**
     * @dev Allows rescuing tokens sent to this contract
     * @param _to  Destination address to send the tokens
     * @param _token  Address of the token being rescued
     * @param _tokens  Amount of tokens to pull
     */
    function _rescueTokens(address _to, address _token, uint256 _tokens) internal {
        require(_tokens != 0, DataServiceRescuableCannotRescueZero());

        if (Denominations.isNativeToken(_token)) payable(_to).transfer(_tokens);
        else SafeERC20.safeTransfer(IERC20(_token), _to, _tokens);

        emit TokensRescued(msg.sender, _to, _tokens);
    }
}

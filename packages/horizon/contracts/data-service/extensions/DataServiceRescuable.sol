// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
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
 * @dev Note that this extension does not provide an external function to set
 * rescuers. This should be implemented in the derived contract.
 */
abstract contract DataServiceRescuable is DataService, IDataServiceRescuable {
    /// @notice List of rescuers and their allowed status
    mapping(address rescuer => bool allowed) public rescuers;

    /**
     * @notice Checks if the caller is a rescuer.
     */
    modifier onlyRescuer() {
        require(rescuers[msg.sender], DataServiceRescuableNotRescuer(msg.sender));
        _;
    }

    /**
     * @notice See {IDataServiceRescuable-rescueGRT}
     */
    function rescueGRT(address to, uint256 tokens) external virtual onlyRescuer {
        _rescueTokens(to, address(_graphToken()), tokens);
    }

    /**
     * @notice See {IDataServiceRescuable-rescueETH}
     */
    function rescueETH(address payable to, uint256 tokens) external virtual onlyRescuer {
        _rescueTokens(to, Denominations.NATIVE_TOKEN, tokens);
    }

    /**
     * @notice Sets a rescuer.
     * @dev Internal function to be used by the derived contract to set rescuers.
     *
     * Emits a {RescuerSet} event.
     *
     * @param _rescuer Address of the rescuer
     * @param _allowed Allowed status of the rescuer
     */
    function _setRescuer(address _rescuer, bool _allowed) internal {
        rescuers[_rescuer] = _allowed;
        emit RescuerSet(_rescuer, _allowed);
    }

    /**
     * @dev Allows rescuing tokens sent to this contract
     * @param _to Destination address to send the tokens
     * @param _token Address of the token being rescued
     * @param _tokens Amount of tokens to pull
     */
    function _rescueTokens(address _to, address _token, uint256 _tokens) internal {
        require(_tokens != 0, DataServiceRescuableCannotRescueZero());

        if (Denominations.isNativeToken(_token)) Address.sendValue(payable(_to), _tokens);
        else SafeERC20.safeTransfer(IERC20(_token), _to, _tokens);

        emit TokensRescued(msg.sender, _to, _tokens);
    }
}

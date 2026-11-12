// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBilling } from "./IBilling.sol";
import { Governed } from "./Governed.sol";
import { Rescuable } from "./Rescuable.sol";

/**
 * @title Banxa Wrapper
 * @dev Wraps the billing contract to provide a custom interface for the Banxa Fulfillment Service
 */
contract BanxaWrapper is Governed, Rescuable {
    // -- State --

    /// The Graph Token contract
    IERC20 public immutable graphToken;

    /// The billing contract
    IBilling public immutable billing;

    // -- Events --

    /**
     * @dev Order fullfilled by Banxa fulfilment service
     */
    event OrderFulfilled(address indexed fulfiller, address indexed to, uint256 amount);

    // -- Errors --

    /**
     * @dev Zero address not allowed.
     */
    error InvalidZeroAddress();

    /**
     * @dev Zero amount not allowed.
     */
    error InvalidZeroAmount();

    /**
     * @notice Constructor function for the contract
     * @param _token Graph Token address
     * @param _billing billing contract address
     */
    constructor(
        IERC20 _token,
        IBilling _billing,
        address _governor
    ) Governed(_governor) {
        if (address(_token) == address(0) || address(_billing) == address(0)) {
            revert InvalidZeroAddress();
        }

        graphToken = _token;
        billing = _billing;
    }

    /**
     * @notice Pulls tokens from sender and adds them into the billing contract for any user
     * Ensure graphToken.approve() is called on the wrapper contract first
     * @param _to  Address that tokens are being added to
     * @param _amount  Amount of tokens to add
     */
    function fulfil(address _to, uint256 _amount) external {
        if (_to == address(0)) {
            revert InvalidZeroAddress();
        }

        if (_amount == 0) {
            revert InvalidZeroAmount();
        }

        graphToken.transferFrom(msg.sender, address(this), _amount);
        graphToken.approve(address(billing), _amount);
        billing.addTo(_to, _amount);

        emit OrderFulfilled(msg.sender, _to, _amount);
    }

    /**
     * @notice Allows the Governor to rescue any ERC20 tokens sent to this contract by accident
     * @param _to  Destination address to send the tokens
     * @param _token  Token address of the token that was accidentally sent to the contract
     * @param _amount  Amount of tokens to pull
     */
    function rescueTokens(
        address _to,
        address _token,
        uint256 _amount
    ) external onlyGovernor {
        _rescueTokens(_to, _token, _amount);
    }
}

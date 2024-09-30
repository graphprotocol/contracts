// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IDataService } from "./IDataService.sol";

/**
 * @title Interface for the {IDataServicePausable} contract.
 * @notice Extension for the {IDataService} contract, adds the ability to rescue
 * any ERC20 token or ETH from the contract, controlled by a rescuer privileged role.
 */
interface IDataServiceRescuable is IDataService {
    /**
     * @notice Emitted when tokens are rescued from the contract.
     * @param from The address initiating the rescue
     * @param to The address receiving the rescued tokens
     * @param token The address of the token being rescued
     * @param tokens The amount of tokens rescued
     */
    event TokensRescued(address indexed from, address indexed to, address token, uint256 tokens);

    /**
     * @notice Emitted when a rescuer is set.
     */
    event RescuerSet(address indexed account, bool allowed);

    /**
     * @notice Thrown when trying to rescue zero tokens.
     */
    error DataServiceRescuableCannotRescueZero();

    /**
     * @notice Thrown when the caller is not a rescuer.
     */
    error DataServiceRescuableNotRescuer(address account);

    /**
     * @notice Rescues GRT tokens from the contract.
     * @dev Declared as virtual to allow disabling the function via override.
     *
     * Requirements:
     * - Cannot rescue zero tokens.
     *
     * Emits a {TokensRescued} event.
     *
     * @param to Address of the tokens recipient.
     * @param tokens Amount of tokens to rescue.
     */
    function rescueGRT(address to, uint256 tokens) external;

    /**
     * @notice Rescues ether from the contract.
     * @dev Declared as virtual to allow disabling the function via override.
     *
     * Requirements:
     * - Cannot rescue zeroether.
     *
     * Emits a {TokensRescued} event.
     *
     * @param to Address of the tokens recipient.
     * @param tokens Amount of tokens to rescue.
     */
    function rescueETH(address payable to, uint256 tokens) external;
}

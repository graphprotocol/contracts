// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || ^0.8.0;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

import { IGraphToken } from "../../token/IGraphToken.sol";

/**
 * @title IL2GraphToken
 * @author Edge & Node
 * @notice Interface for the L2 Graph Token contract that extends IGraphToken with L2-specific functionality
 */
interface IL2GraphToken is IGraphToken {
    // Events
    /**
     * @notice Emitted when tokens are minted through the bridge
     * @param account The account that received the minted tokens
     * @param amount The amount of tokens minted
     */
    event BridgeMinted(address indexed account, uint256 amount);

    /**
     * @notice Emitted when tokens are burned through the bridge
     * @param account The account from which tokens were burned
     * @param amount The amount of tokens burned
     */
    event BridgeBurned(address indexed account, uint256 amount);

    /**
     * @notice Emitted when the gateway address is set
     * @param gateway The new gateway address
     */
    event GatewaySet(address gateway);

    /**
     * @notice Emitted when the L1 address is set
     * @param l1Address The new L1 address
     */
    event L1AddressSet(address l1Address);

    // Public state variables (view functions)
    /**
     * @notice Get the gateway contract address
     * @return The address of the gateway contract
     */
    function gateway() external view returns (address);

    /**
     * @notice Get the L1 contract address
     * @return The address of the L1 contract
     */
    function l1Address() external view returns (address);

    // Functions

    /**
     * @notice Initialize the L2 token contract
     * @param owner The owner address for the contract
     */
    function initialize(address owner) external;

    /**
     * @notice Set the gateway address.
     * @param gw Address of the gateway
     */
    function setGateway(address gw) external;

    /**
     * @notice Set the L1 address.
     * @param addr Address of the L1 contract
     */
    function setL1Address(address addr) external;

    /**
     * @notice Mint tokens for a bridge transfer.
     * @param account Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function bridgeMint(address account, uint256 amount) external;

    /**
     * @notice Burn tokens for a bridge transfer.
     * @param account Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function bridgeBurn(address account, uint256 amount) external;
}

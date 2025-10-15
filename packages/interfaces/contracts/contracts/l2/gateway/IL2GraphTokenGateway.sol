// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;
pragma abicoder v2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

/**
 * @title IL2GraphTokenGateway
 * @author Edge & Node
 * @notice Interface for the L2 Graph Token Gateway contract that handles token bridging on L2
 */
interface IL2GraphTokenGateway {
    // Structs
    struct OutboundCalldata {
        address from;
        bytes extraData;
    }

    // Events
    /**
     * @notice Emitted when a deposit from L1 is finalized on L2
     * @param l1Token The L1 token address
     * @param from The sender address on L1
     * @param to The recipient address on L2
     * @param amount The amount of tokens deposited
     */
    event DepositFinalized(address indexed l1Token, address indexed from, address indexed to, uint256 amount);

    /**
     * @notice Emitted when a withdrawal from L2 to L1 is initiated
     * @param l1Token The L1 token address
     * @param from The sender address on L2
     * @param to The recipient address on L1
     * @param l2ToL1Id The L2 to L1 message ID
     * @param exitNum The exit number
     * @param amount The amount of tokens withdrawn
     */
    event WithdrawalInitiated(
        address l1Token,
        address indexed from,
        address indexed to,
        uint256 indexed l2ToL1Id,
        uint256 exitNum,
        uint256 amount
    );

    /**
     * @notice Emitted when the L2 router address is set
     * @param l2Router The new L2 router address
     */
    event L2RouterSet(address l2Router);

    /**
     * @notice Emitted when the L1 token address is set
     * @param l1GRT The L1 GRT token address
     */
    event L1TokenAddressSet(address l1GRT);

    /**
     * @notice Emitted when the L1 counterpart address is set
     * @param l1Counterpart The L1 counterpart gateway address
     */
    event L1CounterpartAddressSet(address l1Counterpart);

    // Functions
    /**
     * @notice Initialize the gateway contract
     * @param controller The controller contract address
     */
    function initialize(address controller) external;

    /**
     * @notice Set the L2 router address
     * @param l2Router The L2 router contract address
     */
    function setL2Router(address l2Router) external;

    /**
     * @notice Set the L1 token address
     * @param l1GRT The L1 GRT token contract address
     */
    function setL1TokenAddress(address l1GRT) external;

    /**
     * @notice Set the L1 counterpart gateway address
     * @param l1Counterpart The L1 counterpart gateway contract address
     */
    function setL1CounterpartAddress(address l1Counterpart) external;

    /**
     * @notice Transfer tokens from L2 to L1
     * @param l1Token The L1 token address
     * @param to The recipient address on L1
     * @param amount The amount of tokens to transfer
     * @param data Additional data for the transfer
     * @return The encoded outbound transfer data
     */
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes memory);

    /**
     * @notice Finalize an inbound transfer from L1 to L2
     * @param l1Token The L1 token address
     * @param from The sender address on L1
     * @param to The recipient address on L2
     * @param amount The amount of tokens to transfer
     * @param data Additional data for the transfer
     */
    function finalizeInboundTransfer(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    ) external payable;

    /**
     * @notice Transfer tokens from L2 to L1 (overloaded version with unused parameters)
     * @param l1Token The L1 token address
     * @param to The recipient address on L1
     * @param amount The amount of tokens to transfer
     * @param unused1 Unused parameter for compatibility
     * @param unused2 Unused parameter for compatibility
     * @param data Additional data for the transfer
     * @return The encoded outbound transfer data
     */
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        uint256 unused1,
        uint256 unused2,
        bytes calldata data
    ) external payable returns (bytes memory);

    /**
     * @notice Calculate the L2 token address for a given L1 token
     * @param l1ERC20 The L1 token address
     * @return The corresponding L2 token address
     */
    function calculateL2TokenAddress(address l1ERC20) external view returns (address);

    /**
     * @notice Get the encoded calldata for an outbound transfer
     * @param token The token address
     * @param from The sender address
     * @param to The recipient address
     * @param amount The amount of tokens
     * @param data Additional transfer data
     * @return The encoded calldata
     */
    function getOutboundCalldata(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external pure returns (bytes memory);
}

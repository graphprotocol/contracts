// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;
pragma abicoder v2;

interface IL2GraphTokenGateway {
    // Structs
    struct OutboundCalldata {
        address from;
        bytes extraData;
    }

    // Events
    event DepositFinalized(address indexed l1Token, address indexed from, address indexed to, uint256 amount);
    event WithdrawalInitiated(
        address l1Token,
        address indexed from,
        address indexed to,
        uint256 indexed l2ToL1Id,
        uint256 exitNum,
        uint256 amount
    );
    event L2RouterSet(address l2Router);
    event L1TokenAddressSet(address l1GRT);
    event L1CounterpartAddressSet(address l1Counterpart);

    // Functions
    function initialize(address controller) external;

    function setL2Router(address l2Router) external;

    function setL1TokenAddress(address l1GRT) external;

    function setL1CounterpartAddress(address l1Counterpart) external;

    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes memory);

    function finalizeInboundTransfer(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    ) external payable;

    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        uint256 unused1,
        uint256 unused2,
        bytes calldata data
    ) external payable returns (bytes memory);

    function calculateL2TokenAddress(address l1ERC20) external view returns (address);

    function getOutboundCalldata(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external pure returns (bytes memory);
}

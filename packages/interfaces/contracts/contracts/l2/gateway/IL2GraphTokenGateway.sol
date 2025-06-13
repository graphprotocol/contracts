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
    function initialize(address _controller) external;

    function setL2Router(address _l2Router) external;

    function setL1TokenAddress(address _l1GRT) external;

    function setL1CounterpartAddress(address _l1Counterpart) external;

    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bytes memory);

    function finalizeInboundTransfer(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable;

    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256 unused1,
        uint256 unused2,
        bytes calldata _data
    ) external payable returns (bytes memory);

    function calculateL2TokenAddress(address l1ERC20) external view returns (address);

    function getOutboundCalldata(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) external pure returns (bytes memory);
}

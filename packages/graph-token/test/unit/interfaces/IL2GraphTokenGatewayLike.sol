// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ITokenGateway } from "@graphprotocol/interfaces/contracts/contracts/arbitrum/ITokenGateway.sol";

interface IL2GraphTokenGatewayLike is ITokenGateway {
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
    event TxToL1(address indexed _from, address indexed _to, uint256 indexed _id, bytes _data);
    event PauseChanged(bool isPaused);
    event NewPauseGuardian(address indexed oldPauseGuardian, address indexed pauseGuardian);

    function initialize(address controller) external;

    function setL2Router(address l2Router) external;

    function setL1TokenAddress(address l1GRT) external;

    function setL1CounterpartAddress(address l1Counterpart) external;

    function l2Router() external view returns (address);

    function l1GRT() external view returns (address);

    function l1Counterpart() external view returns (address);

    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes memory);

    function getOutboundCalldata(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external pure returns (bytes memory);

    function setPaused(bool newPaused) external;

    function paused() external view returns (bool);

    function setPauseGuardian(address newPauseGuardian) external;

    function pauseGuardian() external view returns (address);
}

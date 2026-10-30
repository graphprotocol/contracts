// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ITokenGateway } from "@graphprotocol/interfaces/contracts/contracts/arbitrum/ITokenGateway.sol";

interface IL1GraphTokenGatewayLike is ITokenGateway {
    event DepositInitiated(
        address l1Token,
        address indexed from,
        address indexed to,
        uint256 indexed sequenceNumber,
        uint256 amount
    );
    event WithdrawalFinalized(
        address l1Token,
        address indexed from,
        address indexed to,
        uint256 indexed exitNum,
        uint256 amount
    );
    event ArbitrumAddressesSet(address inbox, address l1Router);
    event L2TokenAddressSet(address l2GRT);
    event L2CounterpartAddressSet(address l2Counterpart);
    event EscrowAddressSet(address escrow);
    event AddedToCallhookAllowlist(address newAllowlisted);
    event RemovedFromCallhookAllowlist(address notAllowlisted);
    event L2MintAllowanceUpdated(
        uint256 accumulatedL2MintAllowanceSnapshot,
        uint256 l2MintAllowancePerBlock,
        uint256 lastL2MintAllowanceUpdateBlock
    );
    event TokensMintedFromL2(uint256 amount);
    event TxToL2(address indexed _from, address indexed _to, uint256 indexed _seqNum, bytes _data);
    event PauseChanged(bool isPaused);
    event NewPauseGuardian(address indexed oldPauseGuardian, address indexed pauseGuardian);

    function initialize(address controller) external;

    function setArbitrumAddresses(address inbox, address router) external;

    function setL2TokenAddress(address l2GRT) external;

    function setL2CounterpartAddress(address l2Counterpart) external;

    function setEscrowAddress(address escrow) external;

    function addToCallhookAllowlist(address newAllowlisted) external;

    function removeFromCallhookAllowlist(address notAllowlisted) external;

    function callhookAllowlist(address account) external view returns (bool);

    function updateL2MintAllowance(uint256 l2IssuancePerBlock, uint256 updateBlockNum) external;

    function setL2MintAllowanceParametersManual(
        uint256 accumulatedAllowance,
        uint256 l2IssuancePerBlock,
        uint256 lastUpdateBlock
    ) external;

    function accumulatedL2MintAllowanceAtBlock(uint256 blockNum) external view returns (uint256);

    function accumulatedL2MintAllowanceSnapshot() external view returns (uint256);

    function l2MintAllowancePerBlock() external view returns (uint256);

    function lastL2MintAllowanceUpdateBlock() external view returns (uint256);

    function totalMintedFromL2() external view returns (uint256);

    function l2GRT() external view returns (address);

    function inbox() external view returns (address);

    function l1Router() external view returns (address);

    function l2Counterpart() external view returns (address);

    function escrow() external view returns (address);

    function counterpartGateway() external view returns (address);

    function getOutboundCalldata(
        address l1Token,
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

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;
pragma abicoder v2;

struct WithdrawData {
    address channelAddress;
    address assetId;
    address payable recipient;
    uint256 amount;
    uint256 nonce;
    address callTo;
    bytes callData;
}

interface ICMCWithdraw {
    function getWithdrawalTransactionRecord(WithdrawData calldata wd) external view returns (bool);

    function withdraw(
        WithdrawData calldata wd,
        bytes calldata aliceSignature,
        bytes calldata bobSignature
    ) external;
}

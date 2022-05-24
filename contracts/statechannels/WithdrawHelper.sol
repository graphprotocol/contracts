// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "./ICMCWithdraw.sol";

interface WithdrawHelper {
    function execute(WithdrawData calldata wd, uint256 actualAmount) external;
}

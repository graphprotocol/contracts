// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.16;

import { WithdrawData } from "./ICMCWithdraw.sol";

interface WithdrawHelper {
    function execute(WithdrawData calldata wd, uint256 actualAmount) external;
}

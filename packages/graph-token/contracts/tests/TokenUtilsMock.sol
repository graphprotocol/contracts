// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// solhint-disable use-natspec

import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";
import { TokenUtils } from "../utils/TokenUtils.sol";

contract TokenUtilsMock {
    function pullTokens(IGraphToken token, address from, uint256 amount) external {
        TokenUtils.pullTokens(token, from, amount);
    }

    function pushTokens(IGraphToken token, address to, uint256 amount) external {
        TokenUtils.pushTokens(token, to, amount);
    }

    function burnTokens(IGraphToken token, uint256 amount) external {
        TokenUtils.burnTokens(token, amount);
    }
}

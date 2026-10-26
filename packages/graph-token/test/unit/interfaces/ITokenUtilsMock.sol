// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphTokenLike } from "./IGraphTokenLike.sol";

interface ITokenUtilsMock {
    function pullTokens(IGraphTokenLike token, address from, uint256 amount) external;

    function pushTokens(IGraphTokenLike token, address to, uint256 amount) external;

    function burnTokens(IGraphTokenLike token, uint256 amount) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

// solhint-disable use-natspec

import { IGraphTallyCollector } from "../horizon/IGraphTallyCollector.sol";

interface IGraphTallyCollectorToolshed is IGraphTallyCollector {
    function authorizations(address signer) external view returns (Authorization memory);
    function tokensCollected(
        address serviceProvider,
        bytes32 collectionId,
        address receiver,
        address payer
    ) external view returns (uint256);
}

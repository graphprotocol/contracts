// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphTokenLike } from "./IGraphTokenLike.sol";

interface IL2GraphTokenLike is IGraphTokenLike {
    event BridgeMinted(address indexed account, uint256 amount);
    event BridgeBurned(address indexed account, uint256 amount);
    event GatewaySet(address gateway);
    event L1AddressSet(address l1Address);

    function initialize(address owner) external;

    function gateway() external view returns (address);

    function l1Address() external view returns (address);

    function setGateway(address gw) external;

    function setL1Address(address addr) external;

    function bridgeMint(address account, uint256 amount) external;

    function bridgeBurn(address account, uint256 amount) external;
}

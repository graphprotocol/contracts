// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

import { IGraphToken } from "../../token/IGraphToken.sol";

interface IL2GraphToken is IGraphToken {
    // Events
    event BridgeMinted(address indexed account, uint256 amount);
    event BridgeBurned(address indexed account, uint256 amount);
    event GatewaySet(address gateway);
    event L1AddressSet(address l1Address);

    // Public state variables (view functions)
    function gateway() external view returns (address);
    function l1Address() external view returns (address);

    // Functions
    function initialize(address _owner) external;

    function setGateway(address _gw) external;

    function setL1Address(address _addr) external;

    function bridgeMint(address _account, uint256 _amount) external;

    function bridgeBurn(address _account, uint256 _amount) external;
}

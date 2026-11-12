// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IManaged } from "@graphprotocol/interfaces/contracts/contracts/governance/IManaged.sol";
import { IGraphProxy } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxy.sol";

interface IManagedMock is IManaged {
    function initialize(address controller) external;

    function checkNotPartialPaused() external view;

    function checkNotPaused() external view;

    function checkOnlyGovernor() external view;

    /// curation, epochManager, rewardsManager, staking, graphToken, graphTokenGateway, gns — in that order
    function resolveAll() external view returns (address[7] memory);

    function acceptProxy(IGraphProxy proxy) external;

    function acceptProxyAndCall(IGraphProxy proxy, bytes calldata data) external;
}

// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IGraphProxy } from "./IGraphProxy.sol";

/**
 * @title IGraphProxyAdmin
 * @dev Empty interface to allow the GraphProxyAdmin contract to be used
 * in the GraphDirectory contract.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IGraphProxyAdmin {
    function getProxyImplementation(IGraphProxy proxy) external view returns (address);

    function getProxyPendingImplementation(IGraphProxy proxy) external view returns (address);

    function getProxyAdmin(IGraphProxy proxy) external view returns (address);

    function changeProxyAdmin(IGraphProxy proxy, address newAdmin) external;

    function upgrade(IGraphProxy proxy, address implementation) external;

    function upgradeTo(IGraphProxy proxy, address implementation) external;

    function upgradeToAndCall(IGraphProxy proxy, address implementation, bytes calldata data) external;

    function acceptProxy(IGraphProxy proxy) external;

    function acceptProxyAndCall(IGraphProxy proxy, bytes calldata data) external;
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

import { IGNS } from "../contracts/discovery/IGNS.sol";
import { IL2GNS } from "../contracts/l2/discovery/IL2GNS.sol";
import { IMulticall } from "../contracts/base/IMulticall.sol";

interface IL2GNSToolshed is IGNS, IL2GNS, IMulticall {
    function nextAccountSeqID(address account) external view returns (uint256);
    function subgraphNFT() external view returns (address);
}

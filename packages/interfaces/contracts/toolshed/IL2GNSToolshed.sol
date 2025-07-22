// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

import { IGNS } from "../contracts/discovery/IGNS.sol";
import { IL2GNS } from "../contracts/l2/discovery/IL2GNS.sol";

interface IL2GNSToolshed is IGNS, IL2GNS {
    function subgraphNFT() external view returns (address);
}

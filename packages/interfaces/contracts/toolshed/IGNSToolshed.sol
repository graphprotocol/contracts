// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

import { IGNS } from "../contracts/discovery/IGNS.sol";

interface IGNSToolshed is IGNS {
    function subgraphNFT() external view returns (address);
}

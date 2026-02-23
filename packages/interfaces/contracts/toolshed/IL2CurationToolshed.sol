// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || ^0.8.0;

// solhint-disable use-natspec

import { ICuration } from "../contracts/curation/ICuration.sol";
import { IL2Curation } from "../contracts/l2/curation/IL2Curation.sol";

interface IL2CurationToolshed is ICuration, IL2Curation {
    function subgraphService() external view returns (address);
}

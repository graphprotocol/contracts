// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ISubgraphService } from "../interfaces/ISubgraphService.sol";

import { Attestation } from "../libraries/Attestation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";

abstract contract AttestationManagerV1Storage {
    bytes32 internal DOMAIN_SEPARATOR;

    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;
}

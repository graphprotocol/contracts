// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IHorizonStaking} from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import {ISubgraphService} from "./ISubgraphService.sol";
import {SubgraphServiceV1Storage} from "./SubgraphServiceStorage.sol";

contract SubgraphService is SubgraphServiceV1Storage, ISubgraphService {
    function register(address provisionId, string calldata url, string calldata geohash, uint256 delegatorQueryFeeCut)
        external
        override
    {
        // Get provision from Staking contract
        // Validate provision parameters meet DS requirements
    }

    function _register(address provisionId, string calldata url, string calldata geohash, uint256 delegatorQueryFeeCut)
        internal
    {}

    function getAllocation(address allocationID) external view returns (Allocation memory) {}
    function slash(address serviceProvider, uint256 slashAmount, uint256 rewardsAmount) external {}
}

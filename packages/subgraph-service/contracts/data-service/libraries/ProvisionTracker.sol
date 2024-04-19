// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

library ProvisionTracker {
    error ProvisionTrackerInsufficientTokens(uint256 tokensAvailable, uint256 tokensRequired);

    function lock(
        mapping(address => uint256) storage self,
        IHorizonStaking graphStaking,
        address serviceProvider,
        uint256 tokens
    ) internal {
        if (tokens == 0) return;

        uint256 tokensRequired = self[serviceProvider] + tokens;
        uint256 tokensAvailable = graphStaking.getTokensAvailable(serviceProvider, address(this));
        if (tokensRequired > tokensAvailable) {
            revert ProvisionTrackerInsufficientTokens(tokensAvailable, tokensRequired);
        }
        self[serviceProvider] += tokens;
    }

    function release(mapping(address => uint256) storage self, address serviceProvider, uint256 tokens) internal {
        if (tokens == 0) return;

        if (tokens > self[serviceProvider]) {
            revert ProvisionTrackerInsufficientTokens(self[serviceProvider], tokens);
        }
        self[serviceProvider] -= tokens;
    }

    function getTokensFree(
        mapping(address => uint256) storage self,
        IHorizonStaking graphStaking,
        address serviceProvider
    ) internal view returns (uint256) {
        uint256 tokensAvailable = graphStaking.getTokensAvailable(serviceProvider, address(this));
        if (tokensAvailable >= self[serviceProvider]) return tokensAvailable - self[serviceProvider];
        else return 0;
    }
}

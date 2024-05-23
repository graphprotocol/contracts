// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IHorizonStaking } from "../../interfaces/IHorizonStaking.sol";

library ProvisionTracker {
    error ProvisionTrackerInsufficientTokens(uint256 tokensAvailable, uint256 tokensRequired);

    function lock(
        mapping(address => uint256) storage self,
        IHorizonStaking graphStaking,
        address serviceProvider,
        uint256 tokens,
        uint32 delegationRatio
    ) internal {
        if (tokens == 0) return;

        uint256 tokensRequired = self[serviceProvider] + tokens;
        uint256 tokensAvailable = graphStaking.getTokensAvailable(serviceProvider, address(this), delegationRatio);
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
        address serviceProvider,
        uint32 delegationRatio
    ) internal view returns (uint256) {
        uint256 tokensAvailable = graphStaking.getTokensAvailable(serviceProvider, address(this), delegationRatio);
        if (tokensAvailable >= self[serviceProvider]) return tokensAvailable - self[serviceProvider];
        else return 0;
    }
}

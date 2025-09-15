// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IHorizonStaking } from "@graphprotocol/interfaces/contracts/horizon/IHorizonStaking.sol";

/**
 * @title ProvisionTracker library
 * @notice A library to facilitate tracking of "used tokens" on Graph Horizon provisions. This can be used to
 * ensure data services have enough economic security (provisioned stake) to back the payments they collect for
 * their services.
 * The library provides two primitives, lock and release to signal token usage and free up tokens respectively. It
 * does not make any assumptions about the conditions under which tokens are locked or released.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library ProvisionTracker {
    /**
     * @notice Thrown when trying to lock more tokens than available
     * @param tokensAvailable The amount of tokens available
     * @param tokensRequired The amount of tokens required
     */
    error ProvisionTrackerInsufficientTokens(uint256 tokensAvailable, uint256 tokensRequired);

    /**
     * @notice Locks tokens for a service provider
     * @dev Requirements:
     * - `tokens` must be less than or equal to the amount of tokens available, as reported by the HorizonStaking contract
     * @param self The provision tracker mapping
     * @param graphStaking The HorizonStaking contract
     * @param serviceProvider The service provider address
     * @param tokens The amount of tokens to lock
     * @param delegationRatio A delegation ratio to limit the amount of delegation that's usable
     */
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
        require(tokensRequired <= tokensAvailable, ProvisionTrackerInsufficientTokens(tokensAvailable, tokensRequired));
        self[serviceProvider] += tokens;
    }

    /**
     * @notice Releases tokens for a service provider
     * @dev Requirements:
     * - `tokens` must be less than or equal to the amount of tokens locked for the service provider
     * @param self The provision tracker mapping
     * @param serviceProvider The service provider address
     * @param tokens The amount of tokens to release
     */
    function release(mapping(address => uint256) storage self, address serviceProvider, uint256 tokens) internal {
        if (tokens == 0) return;
        require(self[serviceProvider] >= tokens, ProvisionTrackerInsufficientTokens(self[serviceProvider], tokens));
        self[serviceProvider] -= tokens;
    }

    /**
     * @notice Checks if a service provider has enough tokens available to lock
     * @param self The provision tracker mapping
     * @param graphStaking The HorizonStaking contract
     * @param serviceProvider The service provider address
     * @param delegationRatio A delegation ratio to limit the amount of delegation that's usable
     * @return true if the service provider has enough tokens available to lock, false otherwise
     */
    function check(
        mapping(address => uint256) storage self,
        IHorizonStaking graphStaking,
        address serviceProvider,
        uint32 delegationRatio
    ) internal view returns (bool) {
        uint256 tokensAvailable = graphStaking.getTokensAvailable(serviceProvider, address(this), delegationRatio);
        return self[serviceProvider] <= tokensAvailable;
    }
}

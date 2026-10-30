// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { MockGraphToken } from "../../mocks/MockGraphToken.sol";

/// Curation stand-in for RewardsManager: pool tokens per deployment, with the signal held as this contract's
/// GRT balance (RewardsManager reads total signal as `graphToken.balanceOf(curation)`).
contract RMCurationMock {
    MockGraphToken public immutable token;
    IRewardsManager public rm;

    mapping(bytes32 subgraphDeploymentId => uint256 tokens) private _poolTokens;

    constructor(MockGraphToken token_) {
        token = token_;
    }

    function setRewardsManager(address rm_) external {
        rm = IRewardsManager(rm_);
    }

    /// Hook first, as Curation.mint does, so the RewardsManager accrues on the old signal.
    function signal(bytes32 sd, uint256 tokens) external {
        rm.onSubgraphSignalUpdate(sd);
        _poolTokens[sd] += tokens;
        token.mint(address(this), tokens);
    }

    /// Hook first, as Curation.burn does.
    function unsignal(bytes32 sd, uint256 tokens) external {
        rm.onSubgraphSignalUpdate(sd);
        _poolTokens[sd] -= tokens;
        token.burn(tokens);
    }

    /// Curation fees from query collection: no RewardsManager hook, as Curation.collect.
    function addFees(bytes32 sd, uint256 tokens) external {
        _poolTokens[sd] += tokens;
        token.mint(address(this), tokens);
    }

    function getCurationPoolTokens(bytes32 sd) external view returns (uint256) {
        return _poolTokens[sd];
    }
}

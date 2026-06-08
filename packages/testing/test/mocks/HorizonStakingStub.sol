// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";

/// @notice Minimal staking stub — only provides getProviderTokensAvailable
/// (needed by RecurringCollector to gate collection).
contract HorizonStakingStub {
    mapping(address => mapping(address => IHorizonStakingTypes.Provision)) public provisions;

    function setProvision(
        address serviceProvider,
        address verifier,
        IHorizonStakingTypes.Provision memory provision
    ) external {
        provisions[serviceProvider][verifier] = provision;
    }

    function getProvision(
        address serviceProvider,
        address verifier
    ) external view returns (IHorizonStakingTypes.Provision memory) {
        return provisions[serviceProvider][verifier];
    }

    function getProviderTokensAvailable(address serviceProvider, address verifier) external view returns (uint256) {
        IHorizonStakingTypes.Provision memory p = provisions[serviceProvider][verifier];
        return p.tokens - p.tokensThawing;
    }

    function isAuthorized(address, address, address) external pure returns (bool) {
        return true;
    }
}

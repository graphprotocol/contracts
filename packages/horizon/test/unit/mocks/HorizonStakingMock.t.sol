// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";

contract HorizonStakingMock {
    mapping(address => mapping(address => IHorizonStakingTypes.Provision)) public provisions;
    mapping(address => mapping(address => mapping(address => bool))) public authorizations;

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

    function isAuthorized(address serviceProvider, address verifier, address operator) external view returns (bool) {
        return authorizations[serviceProvider][verifier][operator];
    }

    function setIsAuthorized(address serviceProvider, address verifier, address operator, bool authorized) external {
        authorizations[serviceProvider][verifier][operator] = authorized;
    }

    function getProviderTokensAvailable(address serviceProvider, address verifier) external view returns (uint256) {
        IHorizonStakingTypes.Provision memory provision = provisions[serviceProvider][verifier];
        return provision.tokens - provision.tokensThawing;
    }
}

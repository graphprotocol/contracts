// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";

/// Mock for the RewardsManager tests.
contract RMEligibilityOracleMock is IProviderEligibility, IERC165 {
    mapping(address indexer => bool eligibility) private _eligible;
    mapping(address indexer => bool set) private _isSet;
    bool private _defaultResponse;

    constructor(bool newDefaultResponse) {
        _defaultResponse = newDefaultResponse;
    }

    function setIndexerEligible(address indexer, bool eligibility) external {
        _eligible[indexer] = eligibility;
        _isSet[indexer] = true;
    }

    function setDefaultResponse(bool newDefaultResponse) external {
        _defaultResponse = newDefaultResponse;
    }

    /// Explicitly set indexers get their value; others get the default response.
    function isEligible(address indexer) external view override returns (bool) {
        if (_isSet[indexer]) {
            return _eligible[indexer];
        }
        return _defaultResponse;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IProviderEligibility).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

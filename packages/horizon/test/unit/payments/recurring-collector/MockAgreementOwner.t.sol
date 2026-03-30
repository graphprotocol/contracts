// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Mock contract approver for testing acceptUnsigned and updateUnsigned.
/// Can be configured to return valid selector, wrong value, or revert.
/// Implements IProviderEligibility for eligibility gate testing.
contract MockAgreementOwner is IAgreementOwner, IProviderEligibility, IERC165 {
    mapping(bytes32 => bool) public authorizedHashes;
    bool public shouldRevert;
    bytes4 public overrideReturnValue;
    bool public useOverride;

    // -- Eligibility configuration --
    // Defaults to true: payers that don't care about eligibility allow all providers.
    // Tests that want to deny must explicitly set a provider ineligible.
    mapping(address => bool) public ineligibleProviders;

    function authorize(bytes32 agreementHash) external {
        authorizedHashes[agreementHash] = true;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setOverrideReturnValue(bytes4 _value) external {
        overrideReturnValue = _value;
        useOverride = true;
    }

    bytes16 public lastBeforeCollectionAgreementId;
    uint256 public lastBeforeCollectionTokens;
    bool public shouldRevertOnBeforeCollection;

    function setShouldRevertOnBeforeCollection(bool _shouldRevert) external {
        shouldRevertOnBeforeCollection = _shouldRevert;
    }

    function beforeCollection(bytes16 agreementId, uint256 tokensToCollect) external override {
        if (shouldRevertOnBeforeCollection) {
            revert("MockAgreementOwner: forced revert on beforeCollection");
        }
        lastBeforeCollectionAgreementId = agreementId;
        lastBeforeCollectionTokens = tokensToCollect;
    }

    bytes16 public lastCollectedAgreementId;
    uint256 public lastCollectedTokens;
    bool public shouldRevertOnCollected;

    function setShouldRevertOnCollected(bool _shouldRevert) external {
        shouldRevertOnCollected = _shouldRevert;
    }

    function afterCollection(bytes16 agreementId, uint256 tokensCollected) external override {
        if (shouldRevertOnCollected) {
            revert("MockAgreementOwner: forced revert on afterCollection");
        }
        lastCollectedAgreementId = agreementId;
        lastCollectedTokens = tokensCollected;
    }

    function afterAgreementStateChange(bytes16, bytes32, uint16) external override {}

    // -- IERC165 --

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IProviderEligibility).interfaceId;
    }

    // -- IProviderEligibility --

    /// @notice Mark a provider as ineligible (default is eligible)
    function setProviderIneligible(address provider) external {
        ineligibleProviders[provider] = true;
    }

    function isEligible(address indexer) external view override returns (bool) {
        return !ineligibleProviders[indexer];
    }
}

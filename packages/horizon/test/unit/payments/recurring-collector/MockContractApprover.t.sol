// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IContractApprover } from "@graphprotocol/interfaces/contracts/horizon/IContractApprover.sol";
import { IRewardsEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibility.sol";

/// @notice Mock contract approver for testing acceptUnsigned and updateUnsigned.
/// Can be configured to return valid selector, wrong value, or revert.
/// Optionally supports IERC165 + IRewardsEligibility for eligibility gate testing.
contract MockContractApprover is IContractApprover, IERC165, IRewardsEligibility {
    mapping(bytes32 => bool) public authorizedHashes;
    bool public shouldRevert;
    bytes4 public overrideReturnValue;
    bool public useOverride;

    // -- Eligibility configuration --
    bool public eligibilityEnabled;
    mapping(address => bool) public eligibleProviders;
    bool public defaultEligible;

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

    function approveAgreement(bytes32 agreementHash) external view override returns (bytes4) {
        if (shouldRevert) {
            revert("MockContractApprover: forced revert");
        }
        if (useOverride) {
            return overrideReturnValue;
        }
        if (!authorizedHashes[agreementHash]) {
            return bytes4(0);
        }
        return IContractApprover.approveAgreement.selector;
    }

    bytes16 public lastBeforeCollectionAgreementId;
    uint256 public lastBeforeCollectionTokens;
    bool public shouldRevertOnBeforeCollection;

    function setShouldRevertOnBeforeCollection(bool _shouldRevert) external {
        shouldRevertOnBeforeCollection = _shouldRevert;
    }

    function beforeCollection(bytes16 agreementId, uint256 tokensToCollect) external override {
        if (shouldRevertOnBeforeCollection) {
            revert("MockContractApprover: forced revert on beforeCollection");
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
            revert("MockContractApprover: forced revert on afterCollection");
        }
        lastCollectedAgreementId = agreementId;
        lastCollectedTokens = tokensCollected;
    }

    // -- ERC165 + IRewardsEligibility --

    /// @notice Enable ERC165 reporting of IRewardsEligibility support
    function setEligibilityEnabled(bool _enabled) external {
        eligibilityEnabled = _enabled;
    }

    /// @notice Set whether a specific provider is eligible
    function setProviderEligible(address provider, bool _eligible) external {
        eligibleProviders[provider] = _eligible;
    }

    /// @notice Set default eligibility for providers not explicitly configured
    function setDefaultEligible(bool _eligible) external {
        defaultEligible = _eligible;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        if (interfaceId == type(IERC165).interfaceId) return true;
        if (interfaceId == type(IRewardsEligibility).interfaceId) return eligibilityEnabled;
        return false;
    }

    function isEligible(address indexer) external view override returns (bool) {
        if (eligibleProviders[indexer]) return true;
        return defaultEligible;
    }
}

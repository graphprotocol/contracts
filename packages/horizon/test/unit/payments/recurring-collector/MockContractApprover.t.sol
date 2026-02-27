// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IContractApprover } from "@graphprotocol/interfaces/contracts/horizon/IContractApprover.sol";

/// @notice Mock contract approver for testing acceptUnsigned and updateUnsigned.
/// Can be configured to return valid selector, wrong value, or revert.
contract MockContractApprover is IContractApprover {
    mapping(bytes32 => bool) public authorizedHashes;
    bool public shouldRevert;
    bytes4 public overrideReturnValue;
    bool public useOverride;

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
}

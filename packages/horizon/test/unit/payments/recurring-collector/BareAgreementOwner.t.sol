// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";

/// @notice Minimal contract payer that implements IAgreementOwner but NOT IERC165.
/// Calling supportsInterface on this contract will revert (no such function),
/// exercising the catch {} fallthrough in RecurringCollector's eligibility gate.
contract BareAgreementOwner is IAgreementOwner {
    mapping(bytes32 => bool) public authorizedHashes;

    function authorize(bytes32 agreementHash) external {
        authorizedHashes[agreementHash] = true;
    }

    function approveAgreement(bytes32 agreementHash) external view override returns (bytes4) {
        if (!authorizedHashes[agreementHash]) return bytes4(0);
        return IAgreementOwner.approveAgreement.selector;
    }

    function beforeCollection(bytes16, uint256) external override {}

    function afterCollection(bytes16, uint256) external override {}
}

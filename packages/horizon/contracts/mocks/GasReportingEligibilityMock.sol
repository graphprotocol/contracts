// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title GasReportingEligibilityMock
 * @author Edge & Node
 * @notice Test-only mock that returns `gasleft() >= MIN_REQUIRED_GASLEFT` from `isEligible`.
 * Encoding the budget check into the return value is the only signal a STATICCALL
 * callee can give (no state writes, no logs), so the boundary discriminator at the
 * caller side is "precheck reverted" vs "got false return → eligibility revert".
 */
contract GasReportingEligibilityMock is IProviderEligibility, IERC165 {
    /// @notice Minimum forwarded `gasleft()` required for `isEligible` to return true.
    uint256 public immutable MIN_REQUIRED_GASLEFT;

    constructor(uint256 minRequiredGasleft_) {
        MIN_REQUIRED_GASLEFT = minRequiredGasleft_;
    }

    /// @inheritdoc IProviderEligibility
    function isEligible(address) external view override returns (bool) {
        return !(gasleft() < MIN_REQUIRED_GASLEFT);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IProviderEligibility).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

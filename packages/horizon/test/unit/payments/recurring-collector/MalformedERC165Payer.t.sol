// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";

/// @notice Malicious payer that returns empty data from supportsInterface(),
/// causing an ABI decoding revert on the caller side that escapes try/catch.
contract MalformedERC165Payer is IAgreementOwner {
    mapping(bytes32 => bool) public authorizedHashes;

    function authorize(bytes32 agreementHash) external {
        authorizedHashes[agreementHash] = true;
    }

    function beforeCollection(bytes16, uint256) external override {}

    function afterCollection(bytes16, uint256) external override {}

    function afterAgreementStateChange(bytes16, bytes32, uint16) external override {}

    /// @notice Responds to supportsInterface with empty returndata.
    /// The call succeeds at the EVM level but the caller cannot ABI-decode the result.
    fallback() external {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            return(0, 0)
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { IDataServiceAgreements } from "@graphprotocol/interfaces/contracts/data-service/IDataServiceAgreements.sol";

/// @dev Mock data service that implements IDataServiceAgreements for RC unit tests.
/// Simply accepts all agreements without validation.
contract MockAcceptCallback is IDataServiceAgreements {
    function acceptAgreement(
        bytes16,
        bytes32,
        address,
        address,
        bytes calldata,
        bytes calldata
    ) external pure override {}
    function afterAgreementStateChange(bytes16, bytes32, uint16) external pure override {}
}

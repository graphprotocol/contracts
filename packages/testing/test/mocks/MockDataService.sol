// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { IDataServiceAgreements } from "@graphprotocol/interfaces/contracts/data-service/IDataServiceAgreements.sol";

/// @dev Mock data service that accepts all agreements/updates without validation.
contract MockDataService is IDataServiceAgreements {
    function acceptAgreement(bytes16, bytes32, address, address, bytes calldata, bytes calldata) external pure {}
    function afterAgreementStateChange(bytes16, bytes32, uint16) external pure {}
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { GraphDirectory } from "./GraphDirectory.sol";

import { DataServiceV1Storage } from "./DataServiceStorage.sol";
import { IDataService } from "./IDataService.sol";
import { ProvisionHandler } from "./utilities/ProvisionHandler.sol";

abstract contract DataService is GraphDirectory, ProvisionHandler, DataServiceV1Storage, IDataService {
    error DataServiceNotAuthorized(address caller, address serviceProvider, address service);
    error DataServiceServicePaymentsNotEnabled();

    modifier onlyProvisionAuthorized(address serviceProvider) {
        if (!graphStaking.isAuthorized(msg.sender, serviceProvider, address(this))) {
            revert DataServiceNotAuthorized(msg.sender, serviceProvider, address(this));
        }
        _;
    }

    constructor(address _controller) GraphDirectory(_controller) {}

    // solhint-disable-next-line no-unused-vars
    function collectServicePayment(
        address serviceProvider,
        bytes calldata data
    ) external virtual override onlyProvisionAuthorized(serviceProvider) {
        revert DataServiceServicePaymentsNotEnabled();
    }

    // solhint-disable-next-line no-unused-vars
    function acceptProvision(
        address indexer,
        bytes calldata _data
    ) external virtual override onlyProvisionAuthorized(indexer) {
        _checkProvisionParameters(indexer);
        _acceptProvision(indexer);
    }
}

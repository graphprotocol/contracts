// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "../interfaces/IGraphPayments.sol";
import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { GraphDirectory } from "./GraphDirectory.sol";

import { DataServiceV1Storage } from "./DataServiceStorage.sol";
import { IDataService } from "./IDataService.sol";
import { ProvisionManager } from "./utilities/ProvisionManager.sol";

abstract contract DataService is GraphDirectory, ProvisionManager, DataServiceV1Storage, IDataService {
    error DataServiceNotAuthorized(address caller, address serviceProvider, address service);
    error DataServiceNotImplemented();

    constructor(address _controller) GraphDirectory(_controller) {}

    function register(
        address serviceProvider,
        bytes calldata
    ) external virtual override onlyProvisionAuthorized(serviceProvider) {
        _acceptProvision(serviceProvider);
    }

    function acceptProvision(
        address serviceProvider,
        bytes calldata
    ) external virtual override onlyProvisionAuthorized(serviceProvider) {
        _acceptProvision(serviceProvider);
    }

    function startService(
        address serviceProvider,
        bytes calldata
    ) external virtual override onlyProvisionAuthorized(serviceProvider) {
        revert DataServiceNotImplemented();
    }

    function collectServicePayment(
        address serviceProvider,
        bytes calldata
    ) external virtual override onlyProvisionAuthorized(serviceProvider) {
        revert DataServiceNotImplemented();
    }

    function stopService(
        address serviceProvider,
        bytes calldata
    ) external virtual override onlyProvisionAuthorized(serviceProvider) {
        revert DataServiceNotImplemented();
    }

    function redeem(IGraphPayments.PaymentTypes, bytes calldata) external virtual override returns (uint256) {
        revert DataServiceNotImplemented();
    }
}
